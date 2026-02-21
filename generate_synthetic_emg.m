function [noisy_signal, clean_signal, t] = generate_synthetic_emg(fs, duration, noise_level, add_50hz, add_baseline)
% =========================================================================
% GENERATE_SYNTHETIC_EMG  —  Yapay EMG Sinyali Üretici
% =========================================================================
%
% AÇIKLAMA:
%   Gerçekçi bir EMG sinyali simüle eder. Sinyal, 3 bileşenden oluşur:
%     1) Temiz EMG benzeri bileşen (bant sınırlı Gaussian gürültü + burst)
%     2) 50 Hz şebeke gürültüsü (isteğe bağlı)
%     3) Baseline wander - düşük frekanslı kayma (isteğe bağlı)
%
% GİRİŞLER:
%   fs          : Örnekleme frekansı [Hz] (örn. 2000)
%   duration    : Sinyal süresi [saniye] (örn. 3)
%   noise_level : Beyaz gürültü şiddeti, 0-2 arası normalize [0=saf, 1=orta, 2=çok gürültülü]
%   add_50hz    : true/false — 50 Hz şebeke gürültüsü ekle
%   add_baseline: true/false — Baseline wander (sürüklenme) ekle
%
% ÇIKIŞLAR:
%   noisy_signal : Gürültülü ham sinyal [N×1 double, mV]
%   clean_signal : Gürültüsüz referans sinyal [N×1 double, mV] (SNR için)
%   t            : Zaman vektörü [N×1 double, saniye]
%
% KULLANIM:
%   [ham, temiz, t] = generate_synthetic_emg(2000, 3, 0.3, true, true);
%   plot(t, ham); hold on; plot(t, temiz);
%
% =========================================================================

% --- Varsayılan değerler ---
if nargin < 3, noise_level = 0.3; end
if nargin < 4, add_50hz    = true; end
if nargin < 5, add_baseline = true; end

% Zaman vektörü oluştur
N = round(fs * duration);           % Toplam örnek sayısı
t = (0:N-1)' / fs;                  % Zaman ekseni [saniye]

% =========================================================================
% ADIM 1: Temiz EMG Benzeri Sinyal Üretimi
% =========================================================================
% Gerçek EMG sinyali aslında kasın motor birimlerinin rastgele ateşlenmesiyle
% oluşur. Basit bir model: bant sınırlı Gaussian gürültü + kasılma burst'leri.

% 1a) Gaussian beyaz gürültüyü bant geçirenle filtrele → EMG benzeri
rng(42);  % Tekrarlanabilirlik için rastgele tohum sabitle
raw_gauss = randn(N, 1);

% Butterworth bandpass filtresi: 20-450 Hz (EMG'nin fizyolojik bandı)
[b_emg, a_emg] = butter(4, [20 450] / (fs/2), 'bandpass');
emg_base = filtfilt(b_emg, a_emg, raw_gauss);

% 1b) Kasılma burst'leri ekle (zaman zaman yükselen aktivite)
% Sinyal üzerinde 2-3 kasılma penceresi oluştur
burst_envelope = zeros(N, 1);
n_bursts = 3;
for i = 1:n_bursts
    % Her burst'in başlangıç zamanı ve süresi
    burst_start  = (i-0.5) * duration/n_bursts;  % saniye
    burst_dur    = 0.3 + 0.4 * rand();            % 0.3-0.7 s arası
    burst_amp    = 0.5 + rand() * 1.0;            % 0.5-1.5 arası genlik

    idx_start = max(1, round(burst_start * fs));
    idx_end   = min(N, round((burst_start + burst_dur) * fs));

    % Hanning penceresiyle yumuşat (gerçekçi kas aktivasyonu)
    win_len = idx_end - idx_start + 1;
    envelope_win = burst_amp * hann(win_len);
    burst_envelope(idx_start:idx_end) = burst_envelope(idx_start:idx_end) + envelope_win;
end

% Burst envelope ile EMG bazını çarp
emg_clean = emg_base .* (0.2 + burst_envelope);  % 0.2: arka plan aktivitesi

% Genliği normalize et (tipik EMG: 0.1-5 mV)
emg_clean = emg_clean / (3 * std(emg_clean));     % ≈ ±0.33 std, mV cinsinden

% Temiz sinyali kaydet
clean_signal = emg_clean;

% =========================================================================
% ADIM 2: Beyaz Gürültü Ekle
% =========================================================================
% noise_level=1 olduğunda sinyal gücüne eşit gürültü eklenir
white_noise = randn(N, 1);
white_noise = white_noise / std(white_noise);       % Normalize et

% Gürültü genliğini sinyal gücüne göre ölçeklendir
signal_rms = rms(emg_clean);
noise_amplitude = noise_level * signal_rms;
noisy_signal = emg_clean + noise_amplitude * white_noise;

% =========================================================================
% ADIM 3: 50 Hz Şebeke Gürültüsü (İsteğe Bağlı)
% =========================================================================
if add_50hz
    % 50 Hz sinüsoidali (harmoniklerle birlikte)
    amp_50  = 0.3 * signal_rms;    % 50 Hz bileşeni
    amp_100 = 0.1 * signal_rms;    % 2. harmonik (100 Hz)
    amp_150 = 0.05 * signal_rms;   % 3. harmonik (150 Hz)

    phase_50  = 2 * pi * rand();   % Rastgele faz
    phase_100 = 2 * pi * rand();
    phase_150 = 2 * pi * rand();

    powerline = amp_50  * sin(2*pi*50*t  + phase_50) + ...
                amp_100 * sin(2*pi*100*t + phase_100) + ...
                amp_150 * sin(2*pi*150*t + phase_150);

    noisy_signal = noisy_signal + powerline;
end

% =========================================================================
% ADIM 4: Baseline Wander - Düşük Frekanslı Kayma (İsteğe Bağlı)
% =========================================================================
if add_baseline
    % Gerçek EMG'de elektrot hareketi veya terleme nedeniyle oluşan
    % yavaş sürüklenme (0.1-2 Hz arası sinüsoidal bileşen)
    amp_bl = 0.8 * signal_rms;      % Baseline wander genliği

    % Birden fazla yavaş bileşen
    f_bl1 = 0.3 + 0.5 * rand();    % 0.3-0.8 Hz
    f_bl2 = 0.8 + 0.7 * rand();    % 0.8-1.5 Hz

    baseline = amp_bl * sin(2*pi*f_bl1*t + 2*pi*rand()) + ...
               (amp_bl/2) * sin(2*pi*f_bl2*t + 2*pi*rand());

    noisy_signal = noisy_signal + baseline;
end

% =========================================================================
% ADIM 5: Çıkış Kontrolü
% =========================================================================
% Sütun vektörü olduğundan emin ol
noisy_signal = noisy_signal(:);
clean_signal = clean_signal(:);
t            = t(:);

% Kısa bilgi çıktısı (MATLAB komut penceresine)
fprintf('[generate_synthetic_emg] Sinyal üretildi:\n');
fprintf('  Fs=%.0f Hz | Süre=%.1f s | N=%d örnek\n', fs, duration, N);
fprintf('  RMS (temiz)=%.4f mV | RMS (gürültülü)=%.4f mV\n', ...
        rms(clean_signal), rms(noisy_signal));
if add_50hz
    fprintf('  50 Hz şebeke gürültüsü: EKLENDI\n');
else
    fprintf('  50 Hz şebeke gürültüsü: yok\n');
end
if add_baseline
    fprintf('  Baseline wander: EKLENDI\n');
else
    fprintf('  Baseline wander: yok\n');
end

end  % function
