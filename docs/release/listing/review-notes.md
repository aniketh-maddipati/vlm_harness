# Notes for App Review

Lumina Editor works on Sony ARW photos in a folder you choose. Here are five to try:

  <link to five ARW files the account holder owns, downloadable without an account>

To try it:
1. Unzip the files into a folder. In Lumina, click Open and choose that folder. (macOS shows a
   folder panel because the app is sandboxed: it reads only folders you pick.)
2. Press Return to keep a photo. The arrow keys move between photos.
3. Press ⌘4 to go to Save, then ⌘Return. Lumina writes a small .xmp file with the rating next to
   each photo you kept. The photos themselves are never changed.

About the network entitlement (com.apple.security.network.client): the app's screens are local
HTML files bundled with the app and shown in WKWebView. In a sandboxed app, WebKit's networking
process does not start without this entitlement, even though every page is loaded from the app
bundle through a custom URL scheme. The app blocks web requests from those pages and makes no network
connections: no account, no analytics, no update checks.

The app has no account, no in-app purchases and no hidden features.
