# Rakazo on el2

One NixOS MicroVM using Cloud Hypervisor hosts the shared Rakazo deployment.
API, worker, PostgreSQL, the sandbox supervisor, and Docker computers all run
inside that VM. Rakazo manages its users within the application. The supervisor
controls the VM's Docker daemon.

The VM and Tailscale Service are named `rakazo`. Additional users share this
deployment and do not create more VMs. The host uses microvm.nix's default
`microvm:kvm` account and TAP setup.

Rakazo's Compose source follows `main`, pinned by `flake.lock`. The app image and
computer base image use the matching `sha-<commit>` tag. The computer adds the
SDK layer below.
Update with `nix flake update rakazo-src`.
The host rebuilds the guest declaratively through microvm.nix. The host Nix store is
exported read-only; Docker data is stored in the guest's persistent disk.

## Configuration and credentials

The DHCP lease and Tailscale advertisement are configured directly in
`nixos/hosts/el2/services/rakazo/default.nix`. The application's public environment
is defined in `guest-os.nix` in the same directory.
`RAKAZO_WEB_BIND=100.64.2.81` uses upstream's listener setting to expose the web
port to el2's Tailscale proxy.

The guest uses `100.64.2.81` from el2's existing `100.64.2.0/24`, outside the
`.100–.200` DHCP pool. The host binds the address to MAC `02:52:00:00:00:01`
in the existing dnsmasq service. DHCP supplies the guest's address, gateway,
and DNS (`100.64.2.254`); no address or route is set statically in the guest.
TAP `rakazo-tap` joins VLAN 642 through `homeRouter.switch.ports`; dnsmasq derives
the `/24` netmask from the existing LAN interface.

The guest has 8 vCPUs, 24576 MiB RAM, and an 81920 MiB sparse ext4 disk, set
directly in `nixos/hosts/el2/services/rakazo/vm.nix`. The volume size only
controls initial creation; changing it does not grow an existing filesystem.

Create `secrets/files/nixos/el2/rakazo-env.age` with `just edit-secret`.
It contains independent random values for:

```dotenv
POSTGRES_PASSWORD=<32 hexadecimal characters>
POSTGRES_APP_PASSWORD=<32 hexadecimal characters>
BETTER_AUTH_SECRET=<64 hexadecimal characters>
ENCRYPTION_KEY=<64 hexadecimal characters>
SCREEN_PROXY_SECRET=<64 hexadecimal characters>
SANDBOX_SUPERVISOR_TOKEN=<64 hexadecimal characters>
KEENABLE_API_KEY=<Keenable API key>
```

The existing el2 recipient rules cover these top-level host secrets. Preserve
`ENCRYPTION_KEY` and the database password when updating the deployment.
Credentials are decrypted on el2 and exported to that VM through a read-only
directory under `/run/rakazo`. Plaintext credentials never enter the Nix store.

`WEB_PROVIDER=keenable` selects Keenable for both internet search and webpage
extraction. Its key is passed to the API and worker from the encrypted environment
above. Update it with `just edit-secret secrets/files/nixos/el2/rakazo-env.age`
and apply with `just nixos`.

The 2026-11-06 upgrade adds `POSTGRES_APP_PASSWORD` for the `rakazo_app` runtime
login; `POSTGRES_PASSWORD` remains the migration owner's password. The published
images Compose file keeps PostgreSQL 16. New content uses upstream's default
encryption at rest, so rolling back across this upgrade requires restoring the
matching database and app data backup, or decrypting content with the newer
version before a downgrade.

Apply with `just nixos` on el2. Configuration or credential changes
restart the MicroVM. Guest services can be inspected from el2:

```sh
systemctl status microvm@rakazo
ssh root@100.64.2.81 systemctl status rakazo
ssh root@100.64.2.81 docker ps
```

Prepare the first owner account before setting `advertised = true`. The service
is available at `https://rakazo.ts.gaof.net`, using el2's
existing certificate and Tailscale DNS synchronization. Registration is closed
with `SIGNUPS_ENABLED=false` in `guest-os.nix`. The upgraded API takes its signup
policy from the environment and mirrors it into the database at each startup;
changing only the database setting no longer closes registration.
The web port is also reachable from the LAN when the VM starts;
`advertised` only controls the Tailscale advertisement. An allowlist requires email
delivery, so the default empty allowlist is used. SMTP and
password recovery are not configured. Users connect their own model credentials
through the UI.

Define the Tailscale Service named `rakazo`
with endpoint `tcp:443` in the admin console, then approve el2 under that Service's
**Service hosts**. Defining the Service creates its DNS record before host approval;
DNS resolution alone does not mean the endpoint is ready. Check approval with:

```sh
tailscale status --json | jq '.Self.CapMap."service-host"'
curl --noproxy '*' https://rakazo.ts.gaof.net
```

The capability map must include `svc:rakazo`. See
[Tailscale's Service host approval instructions](https://tailscale.com/docs/features/tailscale-services#step-3-approve-a-service-host).

If the instance was advertised before its Service was defined and el2 does not
appear in **Service hosts**, re-advertise that instance after defining the Service:

```sh
tailscale serve drain svc:rakazo
tailscale serve advertise svc:rakazo
```

## Computer tools and Skills

`computer.nix` extends the pinned upstream computer image with:

- Long-file transcription: `transcribe-audio` and `estimate-transcription-time`,
  reusing the existing external ASR services and the shared Hermes scripts.
- Office/OCR: LibreOffice Writer, Calc and Impress, Tesseract English/simplified
  Chinese, qpdf, document Python libraries, and the locked docx/pptxgenjs Node
  dependencies copied directly from the existing `pkgs.node-docx` package.
  Node scripts find these modules through `NODE_PATH`.
- Media: ffmpeg/ffprobe and yt-dlp with curl-cffi and bundled EJS scripts.
  Node 22 is installed for JavaScript challenge solving; use `--js-runtimes node`.
- The native Codex CLI package pinned by `pkgs/codex.nix`, including its companion
  resources. The image does not configure Codex authentication or copy chat-model
  credentials; users can configure CLI authorization separately later.

Complete Skill resources live under `/opt/rakazo/skills/`. The `docx`, `xlsx`,
`pdf` and `pptx` Skills come from the existing `anthropic-skills` Flake input;
their upstream scripts and references are preserved, with an appended environment
note explaining how to resolve relative paths in Rakazo. Local
`audio-transcription`, `video-processing` and `codex` Skills use Rakazo's `shell`
and `attach_file` interfaces. Long jobs run independently with `nohup` and report
through workspace log/result files. Deliverables go in the Bot's `exports/`.

Web uploads currently retain Rakazo's default 10 MiB per-file limit. Larger media
can be downloaded into the Bot's computer from a URL and processed there.
The upstream attachment allowlist accepts PDF, XLSX and ZIP, but not DOCX or PPTX.
Bundle Word/PowerPoint originals in ZIP for upload or delivery.

Installing these files in the image does not register them in the application.
Import each `/opt/rakazo/skills/<name>/SKILL.md` through Rakazo's Skills library
for the relevant user. The existing two users have the seven additional Skills
installed; new users need their own imports. Existing computers must receive the
new image through Rakazo's native computer update, which retains their home
files; changing only the supervisor's default image does not replace them.

## Tushare SDK and Skill

`nixos/hosts/el2/services/rakazo/computer.nix` also installs Tushare 1.4.29 with
the image's existing uv
into its existing system Python, and adds the official Skill/reference files at
`/opt/rakazo/skills/tushare-data/`. No additional Python installation or venv is
created. The image retains the upstream desktop entrypoint and runtime user.

The guest builds this image before starting Compose and configures the supervisor
to use it. Its tag derives from the Nix build context, so changing the upstream
commit, SDK version, or Skill files changes the image tag. New and recreated
computers receive the SDK automatically. The build downloads dependencies from
PyPI; the SDK version is pinned, while its transitive dependencies are resolved
at build time.

The [official Skill](https://github.com/waditu-tushare/skills/tree/5e12b31d09123e262c5fb38564e80c26d05cb830/tushare-data)
is pinned in `computer.nix`; `tushare-environment.md` supplies the local execution
instructions. Import the resulting `/opt/rakazo/skills/tushare-data/SKILL.md`
through Rakazo's native Skill interface as `/tushare`. Imported Skills belong to
the importing user and Space; **Agent Secrets** belong to the Space. Each of the
two Tushare users has its own Skill import and encrypted `TUSHARE_TOKEN` record,
using the same token and sharing its permissions and quota. New accounts do not
inherit either configuration automatically.

Agent shell commands use `python3` and receive the token as an environment
variable. Do not put it in the image, Nix configuration, Skill text, or scripts.
The SDK defaults to HTTP; the Skill explicitly initializes it with HTTPS:

```python
import os
import tushare as ts

pro = ts.pro_api(os.environ["TUSHARE_TOKEN"])
pro._DataApi__http_url = "https://api.waditu.com/dataapi"
```

Save chat exports under the bot workspace's `exports/` and use `attach_file`
with a relative path. Files shared between bots can also be copied to
`/home/rakazo/shared/tushare/`.

Verified on 2026-10-06 through the existing `helper`: the Agent read the Skill,
used `/usr/bin/python3` without a venv or package installation, queried Tushare
over HTTPS, and attached CSVs. SSE's 20241001–20241006 calendar returned 6 rows;
`000001.SZ`'s 20240930 daily data returned 1 row. Downloaded artifacts matched
the computer's files. The token was absent from Skill text, run events, and the
image build context.

## Network and capacity

The guest joins the existing VLAN 642 like the Incus VMs and uses the shared
home-router and edge-firewall policies. No Rakazo-specific gateway, route,
DHCP firewall rule, or input/forward rules are added. LAN access, including el2
and the other devices, is available for Rakazo tasks. Public IPv4 egress uses
el2's existing outlets.

Cloud Hypervisor ballooning enables free-page reporting. Actual host memory is
measured through the VMM process's `smaps_rollup`, together with guest memory and
Docker statistics. The shared guest has a 24576 MiB ceiling.
`RAKAZO_COMPUTER_MEMORY=8g` sets each computer's memory limit to 8 GiB; the CPU
limit remains 2. Existing computer containers also need their Docker memory and
memory-swap limits updated to 8 GiB; this retains the no-swap policy.

On 2026-09-30, the pilot's VMM and virtiofs processes together measured about
2.6 GiB PSS with its computer stopped and 3.6 GiB with one Chromium desktop.
This was an idle application/desktop test without model inference or concurrent
user workloads. The owner session and a workspace file were verified
across a VM restart, and a logical PostgreSQL dump was created and inspected.
First desktop provisioning completed
in 5.23 seconds after fixing the app network's gateway priority; web and supervisor
retain their app-network default gateway when computer networks are attached.

el2 currently boots with `mitigations=off`. Separate guest kernels do not restore
the disabled host CPU speculative-execution mitigations.

## Persistence and recovery

The guest's `/var` is stored in
`/pool1/services/rakazo/var.img`. It contains Docker images,
PostgreSQL, agent homes, browser profiles, and persistent SSH host keys. The
encrypted `pool1/services` dataset is already snapshotted and replicated to nfs
by znapzend. Active-VM disk snapshots are crash-consistent; the guest also writes
a logical PostgreSQL dump daily at 02:00 to
`/var/lib/rakazo/backups/database.dump`.

Keep `advertised = false` and stop the MicroVM before replacing `var.img`
from a snapshot. Restore its
matching encrypted credentials, preserve the disk owner, and start the VM again.
Verify the owner account and closed registration before advertising the service.
The database dump can be inspected with `pg_restore --list` inside the PostgreSQL container.

The 2026-11-06 upgrade to `46e95fa8314324cbcf6e4e33c7ed06dbbc68b923`
was rehearsed on a restored database dump before applying it. A stopped-VM
snapshot is retained at
`pool1/services@rakazo-pre-upgrade-20261106T055324Z`; recover only its
`rakazo/var.img`, since that dataset also contains other services. The previous
encrypted credentials, logical dump, and deployment records are kept separately
on el2 in `~yifan/.local/state/rakazo-upgrade-20261106/` (owner-only access).
That deployment preserves the running host's unrelated service configuration
through a local `deployment.nix` overlay; a later plain `just nixos` also applies
any differences between the repository and those preserved services.

The capability rollout on 2026-11-06 updated both existing computers through
Rakazo's native update queue and imported `audio-transcription`, `video-processing`,
`codex`, `docx`, `xlsx`, `pdf`, and `pptx` for both users. All 22 recorded
non-hidden home/artifact files retained their checksums. Its stopped-VM snapshot
is `pool1/services@rakazo-pre-capabilities-20261106T093459Z`; the matching logical
dump, file manifests, and before/after system paths are in
`~yifan/.local/state/rakazo-capabilities-20261106/`.

Validation covered DOCX/PPTX creation, XLSX formula recalculation, Office-to-PDF
conversion, English/Chinese OCR on an image-only PDF, public sample video download,
trimming/transcoding, and audio conversion. A 330-second, 10560078-byte test recording
was transcribed by the external service in 6.709 seconds with 48 timestamped
segments. Node 22.23.3 was recognized by yt-dlp's JS runtime discovery; Codex CLI
0.167.0 starts successfully, while authenticated coding runs remain untested by
request. For mixed Chinese/English OCR, select `chi_sim+eng` and page segmentation
appropriate to the scan's layout.

Browser end-to-end validation on 2026-11-06 signed in as `yifan@rakazo.invalid`
and sent short requests to the existing `helper`, without tool names or execution
instructions (except explicitly requesting Codex for the delegation check):

| Request | Verified result after downloading from chat |
| --- | --- |
| 把这个英文录音转成文字。 | A 330-second file (an 11-second public excerpt looped 30 times) produced a 3107-character transcript with 28 recognized repetitions; this checks the file workflow, not transcription accuracy. |
| 把这份扫描预算表做成能自动合计的 Excel。 | Three scanned rows matched; `=SUM(B3:B5)` was preserved with cached value 500. |
| 做一份 Rakazo 简介，给我 Word、PDF 和一页 PPT。 | ZIP contained readable DOCX, a one-page PDF with legible Chinese, and a one-slide PPTX. PDF also downloaded separately. |
| 下载这个视频，截取前3秒并提取音频：[MDN sample](https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4) | Downloaded MP4 had audio/video and duration 3.003 s; extracted M4A had audio only and duration 5.055 s. |
| 用 Codex 写一个命令行待办清单工具。 | Bot invoked Codex CLI, observed HTTP 401, and reported that authorization was required; no code was generated. |
| 做一页介绍太阳系的 PPT。 | After redeployment, a readable one-slide PPTX was downloaded in ZIP. No Skill-file or attachment-type refusal recurred; packaging recovered from one interpreter-heredoc refusal. |

The browser runs exposed Skill-environment mismatches missed by container smoke
tests: the shell guard rejects `$!` and interpreter heredocs, supporting Skill
files are available through `shell` rather than `skill_read`, and DOCX/PPTX need
ZIP delivery. The managed instructions now account for these constraints.
The standard-library ZIP command and all three background-command examples were
also checked against the deployed desktop guard. The original interpreter-heredoc
refusal reproduced, while the documented commands were accepted.

Installer configurations disable the MicroVM host module.

Sources: [microvm.nix](https://github.com/microvm-nix/microvm.nix),
[Rakazo self-hosting](https://github.com/elie222/rakazo/blob/v0.1.6/docs/self-host.md).
