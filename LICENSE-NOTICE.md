# License notice

There are two separate licenses involved. Please keep them apart.

## 1. This template (MIT)

The template's own files (Docker Compose file, Dockerfile, nginx/MinIO configuration,
shell scripts, configuration templates, documentation) are licensed under the MIT License,
see [`LICENSE`](LICENSE). The MIT license covers **only these template files**. It does
**not** cover `patches/` (see section 3).

## 2. ArtCraft / artcraft-services (ArtCraft License, NOT MIT)

This repository does **not** contain or redistribute ArtCraft source files, SQL,
configuration files or assets. The only upstream-derived content is the small diff
context inside `patches/` (section 3). The Docker build downloads
`storytold/artcraft-services` at the commit pinned in `UPSTREAM.lock` directly from
GitHub. That code, and every image or binary you build from it, is governed by the
ArtCraft License:

https://github.com/storytold/artcraft-services/blob/d950e57352a1b28c9296f69f8ae4eff43877de21/LICENSE.md

Summary (not legal advice; the original text governs). The ArtCraft License is a
"fair source" license, not an OSI open-source license:

- You may use, copy, modify and compile it for your own **private, personal** purposes.
- You may **not** sell the ArtCraft software commercially.
- You may **not** use the code to develop a competing business or product.
- You may **not** fork it to remove ArtCraft community or donation links or paid model services.
- You may **not** use the ArtCraft name, logo or mascot characters to promote your business without permission.

Do not publish images built from this template to public registries, and do not
operate it as a service for others.

## 3. `patches/` (ArtCraft License, NOT MIT)

`patches/backend/*.patch` and `patches/frontend/*.patch` are small unified diffs that modify
ArtCraft source code. They contain short excerpts of upstream code as diff context and are
derivative works of ArtCraft. They are offered **under the ArtCraft License, for private
personal use only**, under the same conditions as upstream (no selling, no competing product,
keep ArtCraft community/donation links and paid model services, no use of the ArtCraft name
or logo for promotion). They do not remove any community, donation or paid-model links.

The patches are applied at image build time (`git apply --check` then `git apply`) to the
commit pinned in `UPSTREAM.lock`. Build with `APPLY_PATCHES=false` to use pristine upstream.

## Trademarks / affiliation

This is an unofficial community template. It is not affiliated with, endorsed by, or
supported by ArtCraft or Storyteller. "ArtCraft" is used only to describe what the
template deploys. No ArtCraft logos or marks are included.

## Storage dependencies

MinIO and mc are built locally from pinned official source commits under AGPL-3.0.
Their license is separate from this template. MinIO Community upstream is no longer
maintained and its legacy binary/image downloads are unavailable. This template uses
the last published server release (including its October 2025 security fix), with
storage accessible only inside the private Docker network or localhost/SSH tunnel.
Review upstream maintenance and security status before storing important data.
Sources: https://github.com/minio/minio and https://github.com/minio/mc .
