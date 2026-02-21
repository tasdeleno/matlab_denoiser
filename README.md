# Delsys Noise Master — Kullanım Kılavuzu

## Dosya Yapısı

```
matlab_denoiser/
├── DelsysNoiseMaster.mlapp        ← Ana GUI uygulaması
├── generate_synthetic_emg.m       ← Yapay EMG üretici
├── advanced_filter.m              ← Filtre fonksiyonu (BW / Notch / Wavelet)
├── velocity_to_angle.m            ← Jiroskop → Açı dönüştürücü
├── compute_metrics.m              ← SNR, RMS, MF hesaplayıcı
└── demo_delsys_noise_master.m     ← Hepsini test eden demo script
```

## Hızlı Başlangıç

### 1. Uygulamayı Açmak

```matlab
>> DelsysNoiseMaster
```

### 2. Demo'yu Çalıştırmak (GUI olmadan)

```matlab
>> demo_delsys_noise_master
```

---

## Sekmeler

### Sekme 1 — Veri İşleme
- **Dosya Yükle**: CSV veya MAT formatında gerçek Delsys verisi yükleyin
- **Filtre Tipi**: Butterworth / Notch / Wavelet seçin
- **Sliderlar**: Parametreler değişince grafik otomatik güncellenir (real-time)
- **Export**: Filtrelenmiş veriyi `.csv` veya `.mat` olarak kaydedin
- **Metrik Paneli**: SNR, RMS, Medyan Frekans anlık gösterilir

### Sekme 2 — Sentetik Test & Analiz
- Örnekleme frekansı, süre ve gürültü seviyesini ayarlayın
- 50 Hz şebeke / baseline wander bileşenlerini açıp kapatın
- Farklı filtre yöntemlerini karşılaştırın

---

## CSV Formatı

Uygulama iki CSV formatını otomatik tanır:

**Format A — Başlıklı, Zamanlı:**
```
Zaman,EMG_CH1,EMG_CH2
0.000,0.123,-0.045
0.001,0.131,-0.038
...
```

**Format B — Sadece Sinyal:**
```
0.123,-0.045
0.131,-0.038
...
```
> Format B'de örnekleme frekansı otomatik 2000 Hz alınır.

## MAT Formatı

Aşağıdaki field adları otomatik tanınır: `data`, `emg`, `signal`, `raw`, `y`
Örnekleme frekansı için: `fs`, `samplerate`, `sr`, `fsamp`

---

## Fonksiyon Referansı

### `generate_synthetic_emg`
```matlab
[ham, temiz, t] = generate_synthetic_emg(fs, duration, noise_level, add_50hz, add_baseline)
```

### `advanced_filter`
```matlab
% Butterworth
p = struct('low',20,'high',450,'order',4);
y = advanced_filter(signal, fs, 'butterworth', p);

% Notch
p = struct('f_notch',50,'Q',35);
y = advanced_filter(signal, fs, 'notch', p);

% Wavelet
p = struct('wavelet','db4','level',5);
y = advanced_filter(signal, fs, 'wavelet', p);
```

### `velocity_to_angle`
```matlab
[angle_deg, angle_rad, t] = velocity_to_angle(gyro_data, fs, ...
    'Unit','deg/s', 'HPF_fc',0.01)
```

### `compute_metrics`
```matlab
m = compute_metrics(signal, fs, ref_signal);
% m.SNR_dB, m.RMS, m.MF_Hz, m.MNF_Hz, m.ZCR_Hz ...
```

---

## Gereksinimler

| Toolbox | Gerekli | Kullanım |
|---------|---------|---------|
| Signal Processing Toolbox | **Zorunlu** | `butter`, `filtfilt`, `iirnotch`, `pwelch` |
| Wavelet Toolbox | Opsiyonel | Sadece Wavelet filtre modu |
