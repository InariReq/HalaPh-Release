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
- `ADVERTISEMENT_VIDEO_URL_HERE` with the advertisement video URL.
- `WEBSITE_URL_HERE` with the hosted showcase website URL.
- `QR_IMAGE_HERE` with a real QR code image or embedded image element.
- Official contact email: `triplineph13@gmail.com`.
- Team content is managed through the manual carousel in `app.js`.
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

## Logo Asset

The website uses a copied logo at `showcase_site/assets/app_icon.png`. If the app logo changes, copy the updated asset from `assets/icons/app_icon.png`.

Do not move, rename, or modify the original Flutter app logo asset.

## Theme Switcher

The website includes a header theme switcher with four themes:

- Light
- Dark
- Burgundy
- Navy

The selected theme is applied immediately and saved in `localStorage`, so the browser remembers the visitor's choice. If no saved preference exists, the site may use the browser's dark-mode preference.

Theme colors are controlled with CSS variables near the top of `styles.css`. Edit the `:root` and `:root[data-theme="..."]` blocks to adjust backgrounds, cards, text, borders, buttons, route accents, and shadows.

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

The Team section uses a manual carousel in `app.js`. Add member photos later in `showcase_site/assets/team/`.

## Team Carousel Photos

Place team photos inside `showcase_site/assets/team/`.

Recommended filenames: `cheong-jia-le.jpg`, `john-jian-carlos.jpg`, `fritzver-valdueza.jpg`, `ervin-amad.jpg`, `maraiah-salivio.jpg`, `jian-dela-cruz.jpg`, `ej-barroga.jpg`, `angela-encarnacion.jpg`, `dhustine-catubig.jpg`, `mark-ian-alimen.jpg`, `allen-ewag.jpg`, `mark-jansen-abilo.jpg`, `ynna-toh.jpg`.

If a photo is missing, the website automatically shows the member initials. The team carousel is manual only. Use the arrows, dots, or keyboard left/right keys.

## Final Pre-Showcase Checklist

- Replace Android APK link.
- Replace QR image.
- Add advertisement video link.
- Check website on phone.
- Check download button.
- Test app on Android.
- Test iOS demo on presenter device.
- Prepare backup APK file.
