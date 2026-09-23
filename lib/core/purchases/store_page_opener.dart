import 'package:tasuke_ai/core/logging/log.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a page of the store's own app — the subscription page, where a
/// subscriber switches plan or cancels.
abstract interface class StorePageOpener {
  /// False when nothing on the device would open [page].
  Future<bool> open(Uri page);
}

/// The one importer of `package:url_launcher`.
final class UrlStorePageOpener implements StorePageOpener {
  const UrlStorePageOpener();

  @override
  Future<bool> open(Uri page) async {
    try {
      // External, not an in-app browser: the https link is claimed by the
      // store app itself, which is signed in; a web view is not.
      return await launchUrl(page, mode: LaunchMode.externalApplication);
    } on Object catch (error, stack) {
      Log.e('could not open $page', error, stack);
      return false;
    }
  }
}
