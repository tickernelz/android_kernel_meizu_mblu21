# Third-party notices

The installable zip is assembled from the official release artifacts below. Nothing is
fetched at boot unless `auto_keybox=1` is set in `/data/adb/tricky_store/integrity.conf`.

| Component | Version | Source | sha256 |
|---|---|---|---|
| Tricky Store | 1.4.1 (245-72b2e84) | `https://github.com/5ec1cff/TrickyStore/releases/download/1.4.1/Tricky-Store-v1.4.1-245-72b2e84-release.zip` | `2f5e73fcba0e4e43b6e96b38f333cbe394873e3a81cf8fe1b831c2fbd6c46ea9` |
| Play Integrity Fork | v19 | `https://github.com/osm0sis/PlayIntegrityFork/releases/download/v19/PlayIntegrityFork-v19.zip` | `83b4d5f32743805c5b5a69361d73b8ab9c095325e24f20711afa1abea837b58f` |

## Tricky Store

Upstream publishes no license file, so no license is granted here beyond the upstream
terms. The artifact is pulled from its official release at build time and is not vendored
in this repository. Redistributing the assembled zip outside the owner's own device is
not granted by this project. Authors: 5ec1cff, aviraxp, Cyberenchanter.

## Play Integrity Fork

GPL-3.0. The full text is `GPL-3.0.txt` in this directory. Copyright osm0sis and
chiteroman @ xda-developers.

## What this module changes in the upstream payloads

* Play Integrity Fork: `post-fs-data.sh` and `service.sh` are shipped as
  `pif-post-fs-data.sh` and `pif-service.sh` and sourced by this module's own scripts.
  Their content is unmodified. `pif.prop` is replaced by this module's default and is
  kept in `/data/adb/modules/playintegrityfix/pif.prop`, where the upstream companion
  library looks for it.
* Tricky Store: `service.apk`, `daemon`, `libtricky_store.so` (arm64), `machikado`,
  `mazoku` and `sepolicy.rule` are unmodified and keep their upstream layout at the
  module root. `build-module.sh` checks each of them against the `.sha256` file that ships
  in the official zip before it is copied. The daemon is started from this module's
  `service.sh`.
* Tricky Store's release zip also carries a default software keybox. It is shipped here as
  `software-keybox.xml` and is only installed when `keybox_mode=software`, or when no
  keybox exists yet. It is a self-signed test chain that Google does not sign.
* The module id stays `playintegrityfix` on purpose: the upstream companion library opens
  `/data/adb/modules/playintegrityfix/classes.dex` and `.../pif.prop` by absolute path.
