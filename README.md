# Delsys Noise Master

Delsys IMU / EMG cihazından gelen sinyaldeki gürültüyü temizlemeye yarayan araç.

İki şekilde kullanılır:
- **Web uygulaması** → `DelsysNoiseMaster.html` dosyasını tarayıcıda aç, MATLAB'a gerek yok
- **MATLAB uygulaması** → `DelsysNoiseMaster.m` dosyasını MATLAB'da çalıştır

---

## Nasıl Açılır?

### Tarayıcıda (kolay yol)

`DelsysNoiseMaster.html` dosyasına çift tıkla, Chrome/Firefox/Edge ile açılır.
Kurulum yok, internet yok, hiçbir şey yüklemeye gerek yok.

### MATLAB'da

```matlab
>> DelsysNoiseMaster
```

Komut penceresine yaz, Enter'a bas.
App Designer'da açmaya **çalışma** — çalışmaz. Komut penceresinden çalıştır.

**Gereksinimler:** MATLAB R2019b+ · Signal Processing Toolbox
*(Wavelet filtresi için Wavelet Toolbox da gerekli — ama olmasa da diğer her şey çalışır)*

---

## Ne İşe Yarar?

### Sekme 1 — Veri İşleme

Elinde Delsys'ten gelen CSV var, üzerine filtre uygulamak istiyorsun.

1. **"Dosya Yükle"** butonuna tıkla → CSV dosyanı seç
2. Sağdaki **kanal seç** menüsünden hangi kanalı görmek istediğini seç
3. Filtre tipini seç:
   - **Butterworth** → EMG için standart, çoğu durumda bu yeterli
   - **Notch** → Prizden gelen 50 Hz gürültüsü varsa bunu seç
   - **Hareketli Ort.** → Basit yumuşatma istiyorsan
   - **Zincir** → Hem Butterworth hem Notch aynı anda
4. Slider'larla parametreleri ayarla
5. **"Filtreyi Uygula"** butonuna bas
6. **"CSV İndir"** ile filtrelenmiş veriyi kaydet

Sağ taraftaki grafikte ham sinyal ve filtrelenmiş sinyal yan yana görünür.
Fare ile grafiğin üzerine gel → tam değeri gösterir.
Mouse tekerleği → yakınlaştır/uzaklaştır.
Tıkla sürükle → kaydır.

**SNR, RMS, Medyan Frekans** değerleri otomatik hesaplanır, üst köşede gösterilir.

---

### Sekme 2 — Sentetik Test

Gerçek verin yoksa ya da filtreyi test etmek istiyorsan burası.

1. Süre ve örnekleme frekansını ayarla
2. Gürültü seviyesini ayarla (% olarak)
3. 50 Hz şebeke gürültüsü / baseline kayması eklemek istiyorsan kutucukları işaretle
4. **"Sentetik EMG Oluştur"** butonuna bas
5. Filtre uygula → sonucu gör

Altta **log paneli** var — her adımda ne olduğunu yazar (SNR kaç dB kazandın, işlem kaç ms sürdü vs.).

---

### Sekme 3 — Jiroskop Analizi

Delsys IMU'dan açısal hız (gyro) verisi aldın, açıya çevirmek istiyorsun.

**Giriş birimi nedir?** Seç: `°/s` (derece/saniye) veya `rad/s`

**Veri kaynağı:**

| Seçenek | Ne yapar |
|---|---|
| Simülasyon | Gerçek veriye gerek yok, parametreleri ayarla → uydurma sinyal oluşturur |
| CSV Yükle | Kendi gyro CSV'ni sürükle bırak veya tıklayıp seç |

**Parametreler (simülasyon için):**
- **Süre** → kaç saniyelik sinyal
- **Örnekleme Frekansı** → kaç Hz (Delsys genelde 148 Hz veya 200 Hz)
- **Sabit Dönüş Hızı** → sensörün ne hızla döndüğü
- **Salınım Genliği** → ileri geri hareket
- **Gürültü** → sensör gürültüsü
- **Lineer Drift** → jiroskopların zamanla kayması

**HPF Kesme Frekansı** → Drift düzeltmenin agresifliği.
`0.05 Hz` genelde iyi başlangıç noktası.
Çok yüksek yaparsan gerçek hareketi de siler.
Çok düşük bırakırsan drift tam temizlenmez.

**"Açıya Çevir"** butonuna bas → sistem şunu yapar:
1. Açısal hızı integre eder (cumtrapz) → ham açı
2. Yüksek geçiren filtre uygular → drift'i çıkarır
3. Grafikleri çizer, metrikleri hesaplar

**"Açı Verisini CSV İndir"** → 4 sütunlu dosya:
`Zaman | Açısal Hız | Ham Açı | Düzeltilmiş Açı`

---

## CSV Formatı

İki format otomatik tanınır, başlık satırı olsa da olmasa da fark etmez:

```
Zaman,EMG_CH1,EMG_CH2
0.000,0.123,-0.045
0.001,0.131,-0.038
```

```
0.123,-0.045
0.131,-0.038
```

İlk sütun artan sayılardan oluşuyorsa zaman sütunu kabul edilir, sinyal ikinci sütundan alınır.
Değilse ilk sütun sinyal olarak alınır.

Örnekleme frekansı CSV'de yazmıyorsa uygulamada elle gir.

---

## Dosyalar

```
DelsysNoiseMaster.html      ← Web uygulaması (tarayıcıda aç)
DelsysNoiseMaster.m         ← MATLAB uygulaması (komut penceresinden çalıştır)
advanced_filter.m           ← Filtre fonksiyonu
velocity_to_angle.m         ← Açısal hız → Açı dönüştürücü
generate_synthetic_emg.m    ← Yapay EMG üretici
compute_metrics.m           ← SNR / RMS / Medyan Frekans hesaplayıcı
demo_delsys_noise_master.m  ← Hepsini test eden örnek script
```

---

## MATLAB Fonksiyonları (komut satırından da kullanılabilir)

```matlab
% Filtre uygula
y = advanced_filter(sinyal, fs, 'butterworth', struct('low',20,'high',450,'order',4));
y = advanced_filter(sinyal, fs, 'notch',       struct('f_notch',50,'Q',35));

% Açısal hız → açı
[aci_derece, aci_radyan, t] = velocity_to_angle(gyro_z, 200, 'HPF_fc', 0.05);

% Yapay EMG üret
[gurultulu, temiz, t] = generate_synthetic_emg(2000, 3, 40, true, false);

% Metrik hesapla
m = compute_metrics(filtrelenmis, fs, temiz_referans);
% m.SNR_dB, m.RMS, m.MF_Hz

% Demo (hepsini görmek için)
demo_delsys_noise_master
```

---

## Sık Karşılaşılan Sorunlar

**"App Designer'da açılmıyor"**
→ Normal, `.m` dosyaları App Designer'da açılmaz. MATLAB komut penceresinden `DelsysNoiseMaster` yaz.

**"Sinyal yükledim ama grafik boş"**
→ Örnekleme frekansını kontrol et. CSV'de zaman sütunu yoksa Fs alanına elle gir.

**"Butterworth filtre bozuyor"**
→ Alt kesme frekansı çok yüksek veya üst kesme çok düşük olabilir. EMG için 20–450 Hz standart başlangıç noktası.

**"Açı hesabı drift yapıyor"**
→ HPF kesme frekansını biraz yükselt (0.05 → 0.1 Hz). Çok uzun kayıtlarda drift kaçınılmazdır.

**"wavelet filtresi çalışmıyor"**
→ Wavelet Toolbox lisansı olmayan MATLAB'larda bu filtre kullanılamaz. Diğer filtreler çalışır.
