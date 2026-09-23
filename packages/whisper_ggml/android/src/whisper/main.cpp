#include "main.h"
#include "whisper.cpp/include/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "whisper.cpp/examples/dr_wav.h"

#include <cstdio>
#include <string>
#include <thread>
#include <mutex>
#include <algorithm>
#include <cstdlib>
#include <vector>
#include <cmath>
#include <iostream>
#include <stdio.h>
#include "json/json.hpp"

using json = nlohmann::json;

char *jsonToChar(json jsonData) noexcept
{
    // Whisper can emit text that splits a multi-byte UTF-8 character at a
    // token boundary; dump() would throw type_error.316 and abort the app
    // across the FFI boundary. Replace invalid bytes with U+FFFD instead.
    std::string result =
        jsonData.dump(-1, ' ', false, json::error_handler_t::replace);
    // malloc, not new[]: callers across the FFI boundary free this
    // with the C allocator (Dart's malloc.free).
    char *ch = (char *)malloc(result.size() + 1);
    strcpy(ch, result.c_str());
    return ch;
}

struct whisper_params
{
    int32_t seed = -1; // RNG seed, not used currently
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;
    // whisper_full_params.no_context: disable cross-segment text conditioning.
    bool no_context = false;
    // whisper_full_params.suppress_non_speech_tokens: drop [BLANK_AUDIO]-style annotations.
    bool suppress_nst = false;

    // Address of a Dart NativeCallable<Void Function(Int32)>; 0 = none.
    uint64_t progress_cb_addr = 0;

    // Park the loaded model in g_model_cache after this request instead of
    // freeing it, so the next request with the same model file skips the
    // multi-second load (issue #26). Off = load-per-request, as always.
    bool keep_model_loaded = false;

    std::string language = "auto";
    std::string prompt;
    std::string model = "models/ggml-tiny.bin";
    std::string audio = "samples/jfk.wav";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

struct whisper_print_user_data
{
    const whisper_params *params;

    const std::vector<std::vector<float>> *pcmf32s;
};

// ---------------------------------------------------------------------------
// Resident model cache (issue #26). transcribe() normally frees its context
// when the request finishes, so every request pays the full model load
// (seconds for the small models and up). A request with keep_model_loaded
// parks its context here instead; the next request with the same model path
// picks it up and skips the load.
//
// Checkout semantics: a request *takes* the parked context (the slot goes
// empty) and parks it again when done, so the mutex is held only for the
// swap — never during a decode. Concurrent requests keep running in
// parallel, each on its own context, exactly as without the cache. The lock
// matters because Dart issues requests from short-lived worker isolates,
// i.e. from changing threads.
// ---------------------------------------------------------------------------
static struct
{
    struct whisper_context *ctx = nullptr; // parked context; nullptr = empty
    std::string model;                     // model path ctx was loaded from
    std::mutex mutex;
} g_model_cache;

json release_model() noexcept
{
    struct whisper_context *parked = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_model_cache.mutex);
        parked = g_model_cache.ctx;
        g_model_cache.ctx = nullptr;
        g_model_cache.model.clear();
    }
    if (parked != nullptr)
    {
        whisper_free(parked);
    }
    json jsonResult;
    jsonResult["@type"] = "releaseModel";
    jsonResult["released"] = parked != nullptr;
    return jsonResult;
}

json transcribe(json jsonBody) noexcept
{
    whisper_params params;

    params.n_threads = jsonBody["threads"];
    params.verbose = jsonBody["is_verbose"];
    params.translate = jsonBody["is_translate"];
    params.language = jsonBody["language"];
    params.print_special_tokens = jsonBody["is_special_tokens"];
    params.no_timestamps = jsonBody["is_no_timestamps"];
    params.model = jsonBody["model"];
    params.audio = jsonBody["audio"];
    params.split_on_word = jsonBody["split_on_word"];
    params.diarize = jsonBody["diarize"];

    // Optional fields: absent / null / empty leaves whisper.cpp defaults.
    if (jsonBody.contains("initial_prompt") && jsonBody["initial_prompt"].is_string())
    {
        params.prompt = jsonBody["initial_prompt"].get<std::string>();
    }
    if (jsonBody.contains("no_context") && jsonBody["no_context"].is_boolean())
    {
        params.no_context = jsonBody["no_context"].get<bool>();
    }
    if (jsonBody.contains("suppress_non_speech_tokens") && jsonBody["suppress_non_speech_tokens"].is_boolean())
    {
        params.suppress_nst = jsonBody["suppress_non_speech_tokens"].get<bool>();
    }
    if (jsonBody.contains("progress_callback") && jsonBody["progress_callback"].is_number_unsigned())
    {
        params.progress_cb_addr = jsonBody["progress_callback"].get<uint64_t>();
    }
    if (jsonBody.contains("keep_model_loaded") && jsonBody["keep_model_loaded"].is_boolean())
    {
        params.keep_model_loaded = jsonBody["keep_model_loaded"].get<bool>();
    }
    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (params.language != "" && params.language != "auto" && whisper_lang_id(params.language.c_str()) == -1)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "error: unknown language = " + params.language;
        return jsonResult;
    }

    if (params.seed < 0)
    {
        params.seed = time(NULL);
    }

    // whisper init: take the parked context when the model path matches
    // (leaving the cache empty while it is in use), otherwise load from disk.
    bool reused_ctx = false;
    struct whisper_context *ctx = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_model_cache.mutex);
        if (g_model_cache.ctx != nullptr && g_model_cache.model == params.model)
        {
            ctx = g_model_cache.ctx;
            g_model_cache.ctx = nullptr;
            g_model_cache.model.clear();
            reused_ctx = true;
        }
    }
    if (ctx == nullptr)
    {
        struct whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = false; // CPU-only build
        ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);
    }
    if (ctx == nullptr)
    {
        // Without this check a missing/corrupt model file crashes in
        // whisper_full instead of surfacing an error response.
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to load model " + params.model;
        return jsonResult;
    }
    // Park or free the context on every exit path (including WAV validation
    // errors: a bad file must not cost the next request a model reload).
    auto release_ctx = [&]() noexcept
    {
        if (!params.keep_model_loaded)
        {
            whisper_free(ctx);
            return;
        }
        struct whisper_context *displaced = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_model_cache.mutex);
            displaced = g_model_cache.ctx;
            g_model_cache.ctx = ctx;
            g_model_cache.model = params.model;
        }
        // A concurrent request may have parked its own context while this
        // one was decoding; only one can stay resident.
        if (displaced != nullptr)
        {
            whisper_free(displaced);
        }
    };
    std::string text_result = "";
    const auto fname_inp = params.audio;
    // WAV input
    std::vector<float> pcmf32;
    {
        drwav wav;
        if (!drwav_init_file(&wav, fname_inp.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = " failed to open WAV file ";
            release_ctx();
            return jsonResult;
        }

        if (wav.channels != 1 && wav.channels != 2)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "must be mono or stereo";
            drwav_uninit(&wav);
            release_ctx();
            return jsonResult;
        }

        if (wav.sampleRate != WHISPER_SAMPLE_RATE)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV file  must be 16 kHz";
            drwav_uninit(&wav);
            release_ctx();
            return jsonResult;
        }

        if (wav.bitsPerSample != 16)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV file  must be 16 bit";
            drwav_uninit(&wav);
            release_ctx();
            return jsonResult;
        }

        int n = wav.totalPCMFrameCount;

        std::vector<int16_t> pcm16;
        pcm16.resize(n * wav.channels);
        drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
        drwav_uninit(&wav);

        // convert to mono, float
        pcmf32.resize(n);
        if (wav.channels == 1)
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[i]) / 32768.0f;
            }
        }
        else
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[2 * i] + pcm16[2 * i + 1]) / 65536.0f;
            }
        }
    }

    {
        if (params.language == "" && params.language == "auto")
        {
            params.language = "auto";
            params.translate = false;
        }
    }
    // run the inference
    {
        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

        wparams.print_realtime = false;
        wparams.print_progress = false;
        wparams.print_timestamps = !params.no_timestamps;
        // wparams.print_special_tokens = params.print_special_tokens;
        wparams.translate = params.translate;
        wparams.language = params.language.c_str();
        wparams.n_threads = params.n_threads;
        wparams.split_on_word = params.split_on_word;
        // tinydiarize speaker-turn detection; needs a *-tdrz model to
        // emit turns, harmless with regular models.
        wparams.tdrz_enable = params.diarize;

        // params.prompt outlives whisper_full(), so the pointer stays valid.
        if (!params.prompt.empty()) {
            wparams.initial_prompt = params.prompt.c_str();
        }
        // A reused context still holds the previous request's decoded text
        // as conditioning history (whisper clears prompt_past only when
        // no_context is set), so force the clear on reuse: a warm request
        // must transcribe exactly like a cold one. initial_prompt is
        // unaffected — whisper re-applies it after the clear.
        wparams.no_context = params.no_context || reused_ctx;
        wparams.suppress_nst = params.suppress_nst;

        if (params.split_on_word) {
            wparams.max_len = 1;
            wparams.token_timestamps = true;
        }

        if (params.progress_cb_addr) {
            // NativeCallable.listener is safe to invoke from whisper's
            // worker thread: it posts to the owning Dart isolate.
            wparams.progress_callback = [](struct whisper_context *, struct whisper_state *, int progress, void * user_data) {
                ((void (*)(int32_t))user_data)((int32_t)progress);
            };
            wparams.progress_callback_user_data = (void *)(uintptr_t)params.progress_cb_addr;
        }

        if (whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size()) != 0)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "failed to process audio";
            release_ctx();
            return jsonResult;
        }

        

        // print result;
        if (!wparams.print_realtime)
        {

            const int n_segments = whisper_full_n_segments(ctx);

            std::vector<json> segmentsJson = {};

            for (int i = 0; i < n_segments; ++i)
            {
                const char *text = whisper_full_get_segment_text(ctx, i);

                std::string str(text);
                text_result += str;
                if (params.no_timestamps)
                {
                    // printf("%s", text);
                    // fflush(stdout);
                } else {
                    json jsonSegment;
                    const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                    const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                    // printf("[%s --> %s]  %s\n", to_timestamp(t0).c_str(), to_timestamp(t1).c_str(), text);

                    jsonSegment["from_ts"] = t0;
                    jsonSegment["to_ts"] = t1;
                    jsonSegment["text"] = text;
                    jsonSegment["speaker_turn_next"] =
                        whisper_full_get_segment_speaker_turn_next(ctx, i);

                    segmentsJson.push_back(jsonSegment);
                }
            }

            if (!params.no_timestamps) {
                jsonResult["segments"] = segmentsJson;
            }
        }
    }
    jsonResult["text"] = text_result;

    release_ctx();
    return jsonResult;
}
extern "C"
{
    FUNCTION_ATTRIBUTE
    char *request(char *body)
    {
        try
        {
            json jsonBody = json::parse(body);
            json jsonResult;

            if (jsonBody["@type"] == "getTextFromWavFile")
            {
                try
                {
                    return jsonToChar(transcribe(jsonBody));
                }
                catch (const std::exception &e)
                {
                    jsonResult["@type"] = "error";
                    jsonResult["message"] = e.what();
                    return jsonToChar(jsonResult);
                }
            }
            if (jsonBody["@type"] == "releaseModel")
            {
                return jsonToChar(release_model());
            }
            if (jsonBody["@type"] == "getVersion")
            {
                jsonResult["@type"] = "version";
                jsonResult["message"] = "lib version: v1.0.1";
                return jsonToChar(jsonResult);
            }

            jsonResult["@type"] = "error";
            jsonResult["message"] = "method not found";
            return jsonToChar(jsonResult);
        }
        catch (const std::exception &e)
        {
            json jsonResult;
            jsonResult["@type"] = "error";
            jsonResult["message"] = e.what();
            return jsonToChar(jsonResult);
        }
    }
}
// ---------------------------------------------------------------------------
// Live (streaming) transcription.
//
// Unlike request()/transcribe(), which load the model on every call, a stream
// keeps one whisper_context alive for the whole session:
//
//   stream_start(json)          -> loads the model (or borrows a parked one
//                                  from g_model_cache), resets state
//   stream_feed(pcm, n)         -> appends 16 kHz mono float samples; re-runs
//                                  inference when >= ~1.5 s of new audio has
//                                  accumulated and returns the partial text
//   stream_append(pcm, n)       -> stream_feed without the inference, for the
//                                  tail Stop hands over
//   stream_stop()               -> final text; frees the context, or parks it
//                                  in g_model_cache when the session was
//                                  started with keep_model_loaded or borrowed
//                                  a parked context (issue #26)
//   stream_abort()              -> stream_stop without the final pass, for a
//                                  cancel
//
// Partials re-decode the whole current window with no_context = true, so a
// wrong early partial does not condition later ones. When the window grows
// past ~25 s its text is committed and the buffer restarts, keeping memory
// and inference time bounded.
// ⚠️ Committed text is final text: stream_stop returns committed + last_text.
// The commit happens in whichever pass crosses 25 s, in practice a preview,
// wherever the audio ends — so a word straddling the cut can be lost from the
// transcript of a note longer than ~25 s. Known and not yet fixed.
//
// An RMS energy gate, evaluated per ~100 ms frame, tracks the last voiced
// sample: inference only runs when new voiced audio has arrived, and the
// decoded window is trimmed shortly after the last voiced sample. Without
// this, whisper hallucinates over trailing silence (repeating earlier text or
// inventing phrases).
// ---------------------------------------------------------------------------

struct whisper_stream_state
{
    struct whisper_context *ctx = nullptr;
    std::vector<float> pcmf32;   // samples of the current window
    size_t n_transcribed = 0;    // window samples covered by the last run
    size_t n_voiced = 0;         // end of the last chunk with speech energy
    float noise_floor = 0.005f;  // adaptive ambient RMS estimate
    float gate_rms_min = 0.0015f;   // absolute minimum speech RMS
    float gate_ratio = 2.5f;        // voiced thold = ratio * noise_floor
    float gate_floor_cap = 0.01f;   // noise_floor cap (loud rooms)
    std::string committed;       // text of windows already committed
    std::string last_text;       // text of the current window's last run
    std::string language = "en";
    std::string prompt;
    std::string model;           // model path ctx was loaded from
    int n_threads = 4;
    bool translate = false;
    bool suppress_nst = false;
    // false: `prompt` primes only the passes whose text is final (see
    // stream_run_inference), not the previews.
    bool prompt_on_previews = true;
    // Park ctx into g_model_cache when the session ends: set when the
    // session asked for keep_model_loaded or borrowed a parked context.
    bool park_on_stop = false;
    std::mutex mutex;
};

static whisper_stream_state g_stream;

// Hand the session context back: park it in g_model_cache when the session
// asked for that (keep_model_loaded) or borrowed the context from there,
// free it otherwise. Caller must hold g_stream.mutex; lock order is
// g_stream.mutex -> g_model_cache.mutex, never the reverse anywhere.
static void stream_dispose_ctx()
{
    if (g_stream.ctx == nullptr) {
        return;
    }
    if (g_stream.park_on_stop) {
        struct whisper_context *displaced = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_model_cache.mutex);
            displaced = g_model_cache.ctx;
            g_model_cache.ctx = g_stream.ctx;
            g_model_cache.model = g_stream.model;
        }
        if (displaced != nullptr) {
            whisper_free(displaced);
        }
    } else {
        whisper_free(g_stream.ctx);
    }
    g_stream.ctx = nullptr;
    g_stream.model.clear();
    g_stream.park_on_stop = false;
}

static const size_t STREAM_STEP_SAMPLES   = (size_t)(1.5 * WHISPER_SAMPLE_RATE);
static const size_t STREAM_COMMIT_SAMPLES = (size_t)(25.0 * WHISPER_SAMPLE_RATE);
// Decode this much audio past the last voiced sample (trailing consonants).
static const size_t STREAM_VOICE_PAD      = (size_t)(0.2 * WHISPER_SAMPLE_RATE);

// Runs whisper_full over the current window. Caller must hold g_stream.mutex.
//
// [final] is true for the pass `stream_stop` runs — the one whose text becomes
// the user's tasks — and false for every live preview while they are talking.
static json stream_run_inference(bool final)
{
    json result;
    result["@type"] = "streamPartial";

    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_realtime   = false;
    wparams.print_progress   = false;
    wparams.print_timestamps = false;
    wparams.translate        = g_stream.translate;
    wparams.language         = g_stream.language.c_str();
    wparams.n_threads        = g_stream.n_threads;
    wparams.no_context       = true;

    // ⚠️ No temperature fallback, one candidate, no timestamps.
    //
    // whisper.cpp's defaults are built for offline transcription of long,
    // clean files: when a decode looks uncertain (low average logprob, high
    // compression ratio) it RETRIES at temperature 0.2, 0.4, 0.6, 0.8 and 1.0,
    // and each retry samples `best_of = 5` candidates. On exactly the audio a
    // phone produces — room noise, a quiet voice, a clip that trails off —
    // "uncertain" is the norm, so one pass became as many as ~26 decoder runs.
    // On a Dimensity 7200 that was over thirty seconds of "Transcribing your
    // voice" for six seconds of speech.
    //
    // Greedy at temperature 0 is what whisper.cpp's own live-stream example
    // uses. Timestamps are skipped because the segment text is all this binding
    // ever reads, and emitting timestamp tokens only lengthens the decode.
    //
    // Re-measured on the host eval (705 clips, greedy vs the same pass with
    // whisper's default fallback): fallback never fired, so it bought nothing,
    // and forcing it through every temperature tripled the final pass. Beam
    // search on the final pass alone was measured too: 5 beams +19% final-pass
    // time for +2.5 points of exact tasks, 3 beams +10% for none. A prompt buys
    // more for less (see below), so the final pass stays greedy as well.
    wparams.temperature_inc  = 0.0f;
    wparams.greedy.best_of   = 1;
    wparams.no_timestamps    = true;
    wparams.suppress_nst = g_stream.suppress_nst;

    // Trim trailing silence from the decode window; decoding it makes
    // whisper hallucinate (repeats or invented phrases).
    const size_t n_decode =
        std::min(g_stream.pcmf32.size(), g_stream.n_voiced + STREAM_VOICE_PAD);
    if (n_decode < (size_t)WHISPER_SAMPLE_RATE / 2) {
        result["text"] = g_stream.committed + g_stream.last_text;
        return result;
    }

    // ⚠️ Bound a repetition loop. With one greedy candidate and no fallback,
    // a decode that never emits end-of-text runs all n_text_ctx/2 - 4 = 220
    // steps — seconds on a phone — and whisper.cpp still returns that text.
    // 10 tokens per second of window is roughly twice the fastest English
    // dictation, so real speech never reaches it; from ~19 s of window the
    // cap is past 220 and changes nothing. English-only (base.en): a
    // multilingual model needs a higher rate.
    wparams.max_tokens = (int)(n_decode * 10 / WHISPER_SAMPLE_RATE) + 32;

    // The prompt is decoded against the encoder output before the first
    // token, which roughly doubles the decoder's share of a pass. On text that
    // becomes tasks it is worth it; on a preview it is not — the final pass
    // replaces that text, and the preview still running when Stop is pressed
    // is part of the wait. So `prompt_on_previews = false` primes the final
    // pass, and the pass that commits a 25-second window (its text is final
    // too, see below), and nothing else.
    const bool commits = n_decode >= STREAM_COMMIT_SAMPLES;
    if (!g_stream.prompt.empty() &&
        (final || commits || g_stream.prompt_on_previews)) {
        wparams.initial_prompt = g_stream.prompt.c_str();
    }

    // ⚠️ Size the encoder to the audio. This is the whole speed story.
    //
    // whisper encodes a fixed 30-second window — 1500 encoder frames — no
    // matter how much audio it is given, and the encoder is most of the cost
    // of a pass. Live transcription runs a pass every ~1.5 s of new speech,
    // each over the entire window from the start, so a 7-second note paid for
    // five or six full 30-second encodes before Stop could even begin its own.
    // On a mid-range phone that was "Finishing up..." for tens of seconds.
    //
    // `audio_ctx` caps the encoder at the audio actually present: 50 frames per
    // second of 16 kHz input (320 samples each), plus ~1.3 s of margin so the
    // last word is never clipped, and a floor below which quality drops off.
    // A 7 s clip encodes ~414 frames instead of 1500.
    //
    // ⚠️ PREVIEWS ONLY. Measured on the whisper.cpp JFK clip: a sized encoder
    // halves the time of a pass (3.7 s -> 1.8 s for 11 s of audio) but costs
    // accuracy — "ask not" came back as "asked not", with a hallucinated
    // "[BLANK_AUDIO]" on the end. That is fine for a preview the user watches
    // scroll past and wrong for the text that becomes their tasks, so the
    // final pass keeps the full 30-second context. The speed still lands where
    // it matters: the preview that is in flight when Stop is pressed now takes
    // half as long, and that is most of what the user waited for.
    if (!final) {
        const int kSamplesPerFrame = WHISPER_SAMPLE_RATE / 50;  // 320
        const int kMarginFrames    = 64;
        const int kMinFrames       = 128;
        const int kMaxFrames       = 1500;                      // 30 s
        const int frames = (int)(n_decode / kSamplesPerFrame) + kMarginFrames;
        wparams.audio_ctx = std::min(kMaxFrames, std::max(kMinFrames, frames));
    }

    if (whisper_full(g_stream.ctx, wparams, g_stream.pcmf32.data(),
                     (int)n_decode) != 0) {
        result["@type"] = "error";
        result["message"] = "failed to process audio";
        return result;
    }

    std::string text;
    const int n_segments = whisper_full_n_segments(g_stream.ctx);
    for (int i = 0; i < n_segments; ++i) {
        text += whisper_full_get_segment_text(g_stream.ctx, i);
    }

    g_stream.last_text = text;
    g_stream.n_transcribed = n_decode;

    if (commits) {
        g_stream.committed += text;
        g_stream.last_text.clear();
        g_stream.pcmf32.erase(g_stream.pcmf32.begin(),
                              g_stream.pcmf32.begin() + n_decode);
        g_stream.n_transcribed = 0;
        g_stream.n_voiced -= std::min(g_stream.n_voiced, n_decode);
    }

    result["text"] = g_stream.committed + g_stream.last_text;
    return result;
}

// Appends to the window and advances the energy gate. Caller must hold
// g_stream.mutex.
//
// ⚠️ The gate runs per ~100 ms frame, not once per call. A call carries
// whatever Dart coalesced while the previous preview ran — 1-3 s on a
// mid-range phone — and one RMS over all of it let a soft last word drown in
// the silence after it: the call failed the gate, n_voiced stayed put, and
// the final pass never decoded the word. The floor constants were tuned at
// one update per ~128 ms recorder chunk, which is what a frame is; a call of
// up to 150 ms is still a single frame, exactly as before.
static void stream_append_locked(const float *pcm, int32_t n_samples)
{
    if (pcm == nullptr || n_samples <= 0) {
        return;
    }
    const size_t base = g_stream.pcmf32.size();
    g_stream.pcmf32.insert(g_stream.pcmf32.end(), pcm, pcm + n_samples);

    const int32_t kFrame = WHISPER_SAMPLE_RATE / 10;  // 100 ms
    int32_t off = 0;
    while (off < n_samples) {
        // A remainder under a frame and a half joins this frame, so no frame
        // is shorter than 50 ms unless the whole call is.
        const int32_t end = (n_samples - off < kFrame + kFrame / 2)
                                ? n_samples
                                : off + kFrame;
        double sum2 = 0.0;
        for (int32_t i = off; i < end; ++i) {
            sum2 += (double)pcm[i] * pcm[i];
        }

        // Adaptive noise floor: falls quickly, rises slowly, so it
        // tracks room tone without absorbing speech. A frame is
        // voiced only when clearly above the floor.
        const float rms = (float)std::sqrt(sum2 / (end - off));
        if (rms < g_stream.noise_floor) {
            g_stream.noise_floor += 0.5f * (rms - g_stream.noise_floor);
        } else {
            g_stream.noise_floor += 0.0005f * (rms - g_stream.noise_floor);
        }
        g_stream.noise_floor =
            std::min(g_stream.noise_floor, g_stream.gate_floor_cap);
        const float voice_thold = std::max(
            g_stream.gate_ratio * g_stream.noise_floor,
            g_stream.gate_rms_min);
        if (rms >= voice_thold) {
            g_stream.n_voiced = base + (size_t)end;
        }
        off = end;
    }
}

// Hands the context back and empties the window. Caller must hold
// g_stream.mutex.
static void stream_end_locked()
{
    stream_dispose_ctx();
    g_stream.pcmf32.clear();
    g_stream.pcmf32.shrink_to_fit();
    g_stream.n_transcribed = 0;
    g_stream.n_voiced = 0;
    g_stream.committed.clear();
    g_stream.last_text.clear();
}

extern "C"
{
    // body: {"model": path, "language": "en", "threads": 4,
    //        "is_translate": false, "initial_prompt": "...",
    //        "prompt_on_previews": true, "keep_model_loaded": false}
    FUNCTION_ATTRIBUTE
    char *stream_start(char *body)
    {
        std::lock_guard<std::mutex> lock(g_stream.mutex);
        json jsonResult;

        json jsonBody = json::parse(body, nullptr, false);
        if (jsonBody.is_discarded() || !jsonBody.contains("model")) {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "stream_start: invalid request body";
            return jsonToChar(jsonResult);
        }

        if (g_stream.ctx != nullptr) {
            // Dispose per the *previous* session's policy before the new
            // session's fields overwrite it.
            stream_dispose_ctx();
        }
        g_stream.pcmf32.clear();
        g_stream.n_transcribed = 0;
        g_stream.n_voiced = 0;
        g_stream.noise_floor = 0.005f;
        g_stream.committed.clear();
        g_stream.last_text.clear();

        std::string model;
        bool keep_model_loaded = false;
        try {
            g_stream.language  = jsonBody.value("language", "en");
            g_stream.n_threads = jsonBody.value("threads", 4);
            g_stream.translate = jsonBody.value("is_translate", false);
            g_stream.suppress_nst = jsonBody.value("suppress_non_speech_tokens", false);
            g_stream.gate_rms_min   = (float)jsonBody.value("gate_rms_min", 0.0015);
            g_stream.gate_ratio     = (float)jsonBody.value("gate_voice_ratio", 2.5);
            g_stream.gate_floor_cap = (float)jsonBody.value("gate_floor_cap", 0.01);
            g_stream.prompt_on_previews =
                jsonBody.value("prompt_on_previews", true);
            g_stream.prompt.clear();
            if (jsonBody.contains("initial_prompt") && jsonBody["initial_prompt"].is_string()) {
                g_stream.prompt = jsonBody["initial_prompt"].get<std::string>();
            }
            keep_model_loaded = jsonBody.value("keep_model_loaded", false);
            model = jsonBody["model"].get<std::string>();
        } catch (const json::exception &e) {
            // A C++ exception escaping extern "C" into FFI would be
            // std::terminate; convert type errors to an error response.
            jsonResult["@type"] = "error";
            jsonResult["message"] =
                std::string("stream_start: bad request: ") + e.what();
            return jsonToChar(jsonResult);
        }

        // Take the parked context when the model path matches (leaving the
        // cache empty while the session uses it), otherwise load from disk.
        // Fresh-session semantics come for free: every stream decode runs
        // with no_context = true, which clears whisper's rolling text
        // history.
        bool borrowed = false;
        {
            std::lock_guard<std::mutex> cache_lock(g_model_cache.mutex);
            if (g_model_cache.ctx != nullptr && g_model_cache.model == model) {
                g_stream.ctx = g_model_cache.ctx;
                g_model_cache.ctx = nullptr;
                g_model_cache.model.clear();
                borrowed = true;
            }
        }
        if (g_stream.ctx == nullptr) {
            whisper_context_params cparams = whisper_context_default_params();
            cparams.use_gpu = false; // CPU-only build
            g_stream.ctx = whisper_init_from_file_with_params(model.c_str(), cparams);
        }
        if (g_stream.ctx == nullptr) {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "stream_start: failed to load model " + model;
            return jsonToChar(jsonResult);
        }
        g_stream.model = model;
        // A borrowed context must go back on stop — the caller that parked
        // it with keep_model_loaded must not silently lose it.
        g_stream.park_on_stop = borrowed || keep_model_loaded;

        jsonResult["@type"] = "streamStarted";
        return jsonToChar(jsonResult);
    }

    // pcm: 16 kHz mono float32 samples in [-1, 1].
    FUNCTION_ATTRIBUTE
    char *stream_feed(const float *pcm, int32_t n_samples)
    {
        std::lock_guard<std::mutex> lock(g_stream.mutex);
        json jsonResult;

        if (g_stream.ctx == nullptr) {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "stream_feed: stream not started";
            return jsonToChar(jsonResult);
        }
        stream_append_locked(pcm, n_samples);

        // Run only when new *voiced* audio arrived — silence alone
        // never triggers a decode.
        if (g_stream.n_voiced > g_stream.n_transcribed &&
            g_stream.pcmf32.size() - g_stream.n_transcribed >= STREAM_STEP_SAMPLES) {
            return jsonToChar(stream_run_inference(/*final=*/false));
        }

        jsonResult["@type"] = "streamPartial";
        jsonResult["text"] = g_stream.committed + g_stream.last_text;
        return jsonToChar(jsonResult);
    }

    // stream_feed without the preview, for the tail Stop hands over: the
    // final pass decodes it anyway. Fed through stream_feed it started one
    // more preview — a whole decode, text thrown away — before that pass.
    FUNCTION_ATTRIBUTE
    char *stream_append(const float *pcm, int32_t n_samples)
    {
        std::lock_guard<std::mutex> lock(g_stream.mutex);
        json jsonResult;

        if (g_stream.ctx == nullptr) {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "stream_append: stream not started";
            return jsonToChar(jsonResult);
        }
        stream_append_locked(pcm, n_samples);

        jsonResult["@type"] = "streamPartial";
        jsonResult["text"] = g_stream.committed + g_stream.last_text;
        return jsonToChar(jsonResult);
    }

    FUNCTION_ATTRIBUTE
    char *stream_stop()
    {
        std::lock_guard<std::mutex> lock(g_stream.mutex);
        json jsonResult;

        if (g_stream.ctx == nullptr) {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "stream_stop: stream not started";
            return jsonToChar(jsonResult);
        }

        // ⚠️ ALWAYS one full-context pass over the voiced audio, not only
        // when new audio arrived after the last preview.
        //
        // Every preview runs with a sized encoder (see stream_run_inference),
        // which is faster and less accurate. If the last preview happened to
        // cover all the audio, the old condition skipped the final pass and
        // returned that preview's text as the result — so the lower-accuracy
        // text became the user's tasks. A silent tail is still trimmed.
        const size_t n_tail = std::min(g_stream.pcmf32.size(),
                                       g_stream.n_voiced + STREAM_VOICE_PAD);
        if (g_stream.n_voiced > 0 &&
            n_tail >= (size_t)WHISPER_SAMPLE_RATE / 2) {
            stream_run_inference(/*final=*/true);
        }

        jsonResult["@type"] = "streamFinal";
        jsonResult["text"] = g_stream.committed + g_stream.last_text;

        stream_end_locked();

        return jsonToChar(jsonResult);
    }

    // stream_stop without the final pass, for a cancel: nobody reads that
    // text, and it is a full-context decode — seconds on a phone. The
    // context is still handed back (freed or parked) exactly as on stop.
    FUNCTION_ATTRIBUTE
    char *stream_abort()
    {
        std::lock_guard<std::mutex> lock(g_stream.mutex);
        json jsonResult;

        stream_end_locked();

        jsonResult["@type"] = "streamAborted";
        return jsonToChar(jsonResult);
    }
}
