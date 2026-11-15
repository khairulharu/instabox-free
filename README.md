# instabox-free

Kumpulan script buat ngidupin mesin **InstaBox free plan** 24/7 tanpa kena hukuman.

## Kenapa script ini ada

InstaBox free plan punya 2 batasan yang bikin mesin gak bisa nyala terus:

1. **Idle pause 30 menit** — kalau 30 menit gak ada aktivitas, mesin otomatis tidur.
2. **Max run 480 menit** — sekali nyala maksimal 8 jam. Kalau kena batas ini, mesin
   dipaksa istirahat dan cooldown-nya makin lama tiap kejadian (5–20 → 60–75 → 120–135 menit).

## Cara kerja `instabox-keepalive.sh`

Dijalanin dari crontab tiap **29 menit**:

| Kondisi mesin | Aksi |
|---|---|
| `running`, umur run < 420 menit | Ping kecil (exec `true`) — menghitung ulang timer idle, jadi mesin gak pernah tidur |
| `running`, umur run ≥ 420 menit | Suspend + resume — mulai run baru 480 menit **tanpa cooldown**. Down-time cuma 30–60 detik sekali tiap ~7,5 jam |
| `paused` | Resume |
| `stopped` | Start |
| cooldown | Diam, tunggu tick berikutnya |

Plus satu blok opsional yang bisa ditambah sendiri kalau perlu: **Redis Cloud
keepalive** — database gratis Redis Cloud dihapus kalau 30 hari gak dapat
tulisan, jadi perlu login + `PUT /api/location` tiap ~6 jam ke aplikasi kamu.
Blok ini sengaja gak masuk repo (kalau mau, tambahkan sendiri di akhir script).

## FAQ

**Kok harus dipasang di luar? Gak bisa langsung di cron-nya VM InstaBox?**

Gak bisa. Idle pause InstaBox itu menidurkan SELURUH VM — proses, cron, semuanya
ikut tidur, dan `crond` di dalem VM gak bisa jalan saat VM tidur. Jadi alarm-nya
harus dipasang di mesin yang hidup terus dan di LUAR InstaBox: PC/laptop lokal,
VPS lain, atau GitHub Actions (cron gratis, granularitas 5 menit). VM-nya emang
keliatan "gak pernah idle" — tapi itu justru efeknya karena di-ping dari luar tiap
29 menit, bukan karena dia mandiri.

## Setup

1. Simpan API key InstaBox ke file:
   ```bash
   echo 'KEY_KAMU' > ~/.instabox_api_key && chmod 600 ~/.instabox_api_key
   ```
2. Edit script, isi `ID` dengan machine id kamu (formatnya `m_xxxxx`).
3. Pasang di crontab:
   ```bash
   chmod +x instabox-keepalive.sh
   crontab -l 2>/dev/null; echo '*/29 * * * * $HOME/instabox-keepalive.sh' | crontab -
   ```
4. Cek log:
   ```bash
   tail -f ~/.instabox_keepalive.log
   ```

## Catatan

- Crontab ini jalan di **system crontab** mesin lokal, terpisah dari cron job
  aplikasi apa pun — matiin cron aplikasi gak akan mematikan keepalive ini.
- Password/API key **tidak** ikut di-commit — script membaca dari file dengan
  permission `600`, jadi aman untuk repo private maupun public.
- Keepalive ini bikin mesin jalan ~24/7. Di free plan itu gratis; di Pro
  ($20/mo + usage), 4 vCPU/8 GiB yang jalan 24/7 kira-kira **$25/bulan** usage
  (sedikit lewat credit $20 yang disertakan).
