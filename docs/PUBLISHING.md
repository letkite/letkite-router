# Publishing the feed

`.github/workflows/publish.yml` builds and signs the feeds and puts them on `get.letkite.com` when a tag `v*` is pushed:

| Path on get.letkite.com | What |
|---|---|
| `openwrt/24.10/` | `Packages`, `Packages.gz`, `Packages.sig` (usign), `*.ipk` |
| `openwrt/25.12/` | `packages.adb` (signed, apk v3), `*.apk` |
| `openwrt/keys/letkite-usign.pub` | the 24.10 feed's public key |
| `openwrt/keys/letkite-apk.pem` | the 25.12 feed's public key |

The workflow derives the public keys from the secret ones, so only the secret halves are stored. Until everything below exists, the workflow logs a notice and stops successfully; nothing is published.

This is the list of what has to be created. **None of it is created by this repository or its workflows.**

## 1. Feed signing keys

Make both on an offline machine, and keep a backup of the secret halves wherever LetKite keeps its other signing keys.

**usign (OpenWrt 24.10, opkg).** `usign` comes from OpenWrt (`staging_dir/host/bin/usign` in the SDK) or from Debian/Ubuntu (`apt install usign`):

```sh
usign -G -s letkite-usign.sec -p letkite-usign.pub -c "LetKite OpenWrt feed"
```

**apk v3 (OpenWrt 25.12).** An ECDSA P-256 key, as OpenWrt's own build uses:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out letkite-apk-private.pem
openssl ec -in letkite-apk-private.pem -pubout -out letkite-apk.pem
```

After the first publish, add both public keys' fingerprints to the README:

- usign: the key id on the comment line of `letkite-usign.pub`;
- apk: `openssl pkey -pubin -in letkite-apk.pem -outform DER | sha256sum`.

## 2. GitHub environment `release`

In the repository settings, create an environment named **`release`**:

- **Deployment branches and tags:** selected tags only, pattern `v*`. No branches.
- **Required reviewers:** recommended. A maintainer then approves each publish.
- **Environment secrets** (exactly these names):

| Secret | Contents |
|---|---|
| `USIGN_SECRET_KEY` | the full contents of `letkite-usign.sec` (both lines) |
| `APK_SIGN_KEY` | the full contents of `letkite-apk-private.pem` (PEM) |
| `AWS_ROLE_ARN` | the ARN of the IAM role in section 3 |
| `FEED_BUCKET` | the name of the S3 bucket behind get.letkite.com |
| `CF_DISTRIBUTION_ID` | the CloudFront distribution ID of get.letkite.com |

Only the `publish` job uses this environment. Pull request and push workflows cannot read these secrets: `pull_request` runs from forks get no secrets, and no workflow here uses `pull_request_target`.

Consider protecting tags `v*` with a tag ruleset, so that only maintainers can create them.

## 3. AWS: IAM role for GitHub OIDC

The workflow uses `aws-actions/configure-aws-credentials` with GitHub's OIDC token. It needs no stored AWS keys.

1. The account needs the OIDC identity provider `token.actions.githubusercontent.com` with audience `sts.amazonaws.com` (it may exist already).
2. Create a role whose trust policy accepts only this repository's `release` environment. Because the environment admits only tags `v*` (section 2), only tag builds can assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:letkite/letkite-router:environment:release"
      }
    }
  }]
}
```

   Optional hardening: put the tag itself into the token's subject, so the role checks it directly. Set the repository's OIDC subject template to include `ref` (REST: `PUT /repos/letkite/letkite-router/actions/oidc/customization/sub` with `{"use_default": false, "include_claim_keys": ["repo", "context", "ref"]}`). Then use `StringLike` on `repo:letkite/letkite-router:environment:release:ref:refs/tags/v*`.

3. Give the role only this policy (us-east-1 is assumed; the S3 and CloudFront ARNs carry no region):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::<FEED_BUCKET>/openwrt/*"
    },
    {
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation"],
      "Resource": "arn:aws:cloudfront::<ACCOUNT_ID>:distribution/<CF_DISTRIBUTION_ID>"
    }
  ]
}
```

   The role cannot read, list or delete anything, and can write only under `openwrt/`.

## 4. S3 prefix and CloudFront

- The bucket behind `get.letkite.com` serves the prefix `openwrt/` like the rest of the site (`agent/`, `channels/`). Check that the distribution's behavior covers `/openwrt/*` and that no bucket policy denies it.
- Cache: the workflow uploads packages with `max-age=86400`, indexes with `max-age=300` and keys with `max-age=3600`. Then it invalidates `/openwrt/<series>/*` and `/openwrt/keys/*`.
- Packages go up first and the index last, so an index never names a package that isn't there yet. Old package files stay; nothing is deleted.

## 5. The bump workflow

`.github/workflows/bump.yml` runs every 6 hours. When the stable channel has a newer agent, it verifies the signed release and opens a pull request with `GITHUB_TOKEN`. That needs:

- Settings → Actions → General → Workflow permissions: **Allow GitHub Actions to create and approve pull requests** turned on. The workflow itself asks only for `contents: write` and `pull-requests: write`, and only in that job.

GitHub does not start other workflows for pull requests opened with `GITHUB_TOKEN`. To run CI on a bump pull request, a maintainer closes and reopens it, or pushes a commit to its branch.

No other repository pushes here, and this repository holds no cross-repository token.

## 6. Publishing a release

1. Merge to `main` with CI green.
2. Bump `PKG_RELEASE` in a package's Makefile if its packaging changed but its version did not.
3. `git tag -s v<X.Y.Z> && git push origin v<X.Y.Z>`.
4. Approve the `release` environment deployment, if reviewers are required.
5. Check:
   - `https://get.letkite.com/openwrt/25.12/packages.adb`;
   - `https://get.letkite.com/openwrt/24.10/Packages.sig`;
   - an install on a test router, following the README.
