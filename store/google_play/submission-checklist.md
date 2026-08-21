# Play Console submission checklist

## App creation

- [ ] Developer identity and contact details verified
- [ ] Create app: **CrispCloud**, default language **English (United States)**
- [ ] Choose **App**, **Free**, category **Tools**
- [ ] Accept Play App Signing; retain the existing upload keystore
- [ ] Package name shown by Play Console is `com.crispstrobe.cloud`

## Store listing

- [ ] Upload `assets/icon-512.png`
- [ ] Upload `assets/feature-graphic-1024x500.png`
- [ ] Upload all four `assets/phone/*.png` screenshots in filename order
- [ ] Paste English and German metadata from `metadata/`
- [ ] Support email: `cstr+privacy@mailbox.org`
- [ ] Website: `https://www.crispstro.be`
- [ ] Privacy policy: `https://crisp-cloud.vercel.app/privacy.html`

## App content

- [ ] Ads: **No**
- [ ] App access: **All functionality is available without developer-owned
      membership**, but reviewers need their own cloud/server account. Add the
      review note below.
- [ ] Target audience: select the actual intended adult/general audience; do
      not actively target children merely because the content is harmless
- [ ] Content rating: complete questionnaire truthfully (file-manager utility,
      no built-in user-generated public feed)
- [ ] Data safety: review `data-safety.md`
- [ ] Government apps: **No**
- [ ] Financial features: **No**, unless payment/financial functionality is
      introduced
- [ ] Health features: **No**
- [ ] News app: **No**

### App-access review note

> CrispCloud is a client for user-selected storage services. The app launches
> without a CrispCloud account. Reviewers can browse local Android storage and
> open the connection screen without credentials. Testing a remote provider
> requires credentials for an account owned by the reviewer; CrispCloud does
> not operate or sell cloud accounts.

## Closed testing

- [ ] Run the `Google Play Bundle` workflow and download the signed AAB
- [ ] Upload the AAB to a closed-testing release
- [ ] Add a tester list or Google Group
- [ ] Copy the Play opt-in URL (not the Firebase URL)
- [ ] Submit the opt-in URL to Testers Community
- [ ] Maintain at least 12 opted-in testers continuously for 14 days
- [ ] Collect feedback and record what changed before requesting production

## Before production

- [ ] Verify the app on at least one physical Android phone
- [ ] Test install/update using the Play closed-track delivery
- [ ] Test sign-in, local SAF access, upload, download, background transfer,
      notifications and account removal
- [ ] Confirm Android vitals and pre-launch report have no blocking crashes
- [ ] Request production access and answer from actual test findings
