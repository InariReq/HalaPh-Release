# HalaPH Showcase Site

This folder contains the standalone professional showcase website for HalaPH.
It is separate from the Flutter app and works without a build step.

## Preview Locally

Open:

```text
showcase_site/index.html
```

You can double-click the file in Finder or open it from a browser.

## Replace Placeholders

Before publishing or presenting, replace these placeholder values:

- `ANDROID_APK_URL_HERE` with the final Android APK download URL.
- `DEMO_VIDEO_URL_HERE` with the demo video URL.
- `WEBSITE_URL_HERE` with the hosted showcase website URL.
- `QR_IMAGE_HERE` with a real QR code image or embedded image element.
- `CONTACT_EMAIL_HERE` with the official contact email.
- Team member names and roles in `index.html`.
- Official slogan if branding changes later.

Current official slogan:

```text
Where Every Trip Meets It's Line
```

## QR Code

1. Host the website first or decide the final public URL.
2. Generate a QR code from the hosted website URL.
3. Replace the `QR_IMAGE_HERE` placeholder in `index.html`.
4. If adding an image file later, place it inside `showcase_site/assets/` and update the QR card markup.

## Hosting Options

Good hosting options:

- GitHub Pages
- Netlify
- Firebase Hosting

Important GitHub Pages note:

If using GitHub Pages built-in branch source, GitHub Pages usually publishes from root or `/docs`. Since this site is in `showcase_site/`, easiest options are:

- Deploy `showcase_site/` directly on Netlify.
- Use GitHub Actions for GitHub Pages.
- Copy `showcase_site` contents to `/docs` later if you want built-in GitHub Pages folder publishing.

## iOS Note

Public iPhone installation is not included without Apple's official distribution program. Use the presenter device for iOS demo during the showcase.

## Android Note

Some Android devices require allowing installs from the browser/file manager before installing an APK.

## Team Note

Replace team member names and roles before final publishing.

## Final Pre-Showcase Checklist

- Replace Android APK link.
- Replace QR image.
- Add demo video link.
- Check website on phone.
- Check download button.
- Test app on Android.
- Test iOS demo on presenter device.
- Prepare backup APK file.
