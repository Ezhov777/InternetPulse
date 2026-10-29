# Server catalog

The bundled catalog contains 10 entries each for the United Kingdom, United States, France, Germany and Spain, plus 9 retained Russian endpoints.

The file URLs were checked on 2026-10-29 from GitHub-hosted runners using a bounded 4096-byte read, rejecting HTML, empty responses and invalid TLS certificates. This verifies reachability from that runner, not sustained throughput or reachability from every ISP.

Sources include provider looking-glass pages and the public Ookla server directory, linked separately in every record. Ookla-directory entries use their public HTTP test image for download only. This is not the Ookla speedtest protocol or an official Ookla client. No compatibility with a provider upload.php endpoint is assumed.

The legacy RastrNet preset retains the previously tested HTTP PUT endpoint. Other entries are download-only.

Run `python3 scripts/check-servers.py` to recheck availability. The check reads a small prefix rather than downloading the full file. Server errors, availability, throughput and routing may change.
