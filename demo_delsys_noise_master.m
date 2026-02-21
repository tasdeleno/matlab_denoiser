% =========================================================================
% DEMO_DELSYS_NOISE_MASTER.m
% =========================================================================
% Bu script, DelsysNoiseMaster uygulamasının tüm yardımcı fonksiyonlarını
% komut satırından test eder. Uygulamayı açmadan önce çalıştırabilirsiniz.
%
% Çalıştırma: MATLAB komut penceresinde >> demo_delsys_noise_master
% =========================================================================

clc; clear; close all;
fprintf('====================================================\n');
fprintf('  DELSYS NOISE MASTER - Demo ve Test Scripti\n');
fprintf('====================================================\n\n');

% =========================================================================
% DEMO 1: Sentetik EMG üretimi
% =========================================================================
fprintf('--- DEMO 1: Sentetik EMG Üretimi ---\n');

fs       = 2000;    % 2 kHz örnekleme (Delsys varsayılanı)
duration = 5;       % 5 saniye
noise_pct = 0.40;   % %40 gürültü seviyesi

[ham, temiz, t] = generate_synthetic_emg(fs, duration, noise_pct, true, true);

figure('Name', 'Demo 1: Sentetik EMG', 'NumberTitle', 'off', ...
       'Position', [50 50 1100 600]);

subplot(3,1,1);
plot(t, temiz, 'g', 'LineWidth', 1);
title('Temiz Referans EMG Sinyali');
xlabel('Zaman (s)'); ylabel('Genlik (mV)');
grid on;

subplot(3,1,2);
plot(t, ham, 'b', 'LineWidth', 0.7);
title('Gürültülü Ham EMG (50 Hz + Baseline Wander ekli)');
xlabel('Zaman (s)'); ylabel('Genlik (mV)');
grid on;

subplot(3,1,3);
% PSD karşılaştırması
win = min(round(length(ham)/4), 1024);
[pxx_h, f_h] = pwelch(ham,   win, [], [], fs);
[pxx_t, f_t] = pwelch(temiz, win, [], [], fs);
semilogy(f_h, pxx_h, 'b', f_t, pxx_t, 'g', 'LineWidth', 1);
legend('Gürültülü', 'Temiz');
title('Güç Spektral Yoğunluğu');
xlabel('Frekans (Hz)'); ylabel('PSD (mV²/Hz)');
xlim([0 500]); grid on;

fprintf('Sinyal üretimi tamamlandı.\n\n');

% =========================================================================
% DEMO 2: Filtre Karşılaştırması
% =========================================================================
fprintf('--- DEMO 2: Filtre Yöntemleri Karşılaştırması ---\n');

% Yöntem 1: Butterworth Bandpass
p_bw = struct('low', 20, 'high', 450, 'order', 4);
y_bw = advanced_filter(ham, fs, 'butterworth', p_bw);

% Yöntem 2: Notch 50 Hz
p_notch = struct('f_notch', 50, 'Q', 35);
y_notch = advanced_filter(ham, fs, 'notch', p_notch);

% Yöntem 3: Wavelet (db4, seviye 5)
p_wv = struct('wavelet', 'db4', 'level', 5);
y_wv = advanced_filter(ham, fs, 'wavelet', p_wv);

% Yöntem 4: Tam zincir (Butterworth + Notch)
y_chain = advanced_filter(y_bw, fs, 'notch', p_notch);

figure('Name', 'Demo 2: Filtre Karşılaştırması', 'NumberTitle', 'off', ...
       'Position', [50 50 1100 750]);

methods = {ham, y_bw, y_notch, y_wv, y_chain};
labels  = {'Ham Sinyal', 'Butterworth BP (20-450 Hz)', ...
           'Notch (50 Hz)', 'Wavelet (db4, L=5)', 'Zincir: BP + Notch'};
colors  = {'b', [0.8 0.2 0.1], [0.1 0.6 0.1], [0.7 0.2 0.8], [1 0.5 0]};

for i = 1:5
    subplot(5,1,i);
    plot(t, methods{i}, 'Color', colors{i}, 'LineWidth', 0.8);
    title(labels{i});
    xlabel('Zaman (s)'); ylabel('mV');
    grid on; xlim([0 duration]);
    ylim([-3 3]);
end

fprintf('Filtre karşılaştırması tamamlandı.\n\n');

% =========================================================================
% DEMO 3: Metrik Hesaplama
% =========================================================================
fprintf('--- DEMO 3: Sinyal Kalite Metrikleri ---\n');

fprintf('\n>> Ham Sinyal Metrikleri:\n');
m_ham = compute_metrics(ham, fs, temiz);

fprintf('\n>> Butterworth Filtrelenmiş Metrikler:\n');
m_bw = compute_metrics(y_bw, fs, temiz);

fprintf('\n>> Wavelet Filtrelenmiş Metrikler:\n');
m_wv = compute_metrics(y_wv, fs, temiz);

fprintf('\n>> Zincir Filtrelenmiş Metrikler:\n');
m_chain = compute_metrics(y_chain, fs, temiz);

% Karşılaştırma tablosu
fprintf('\n=== SNR KARŞILAŞTIRMA TABLOSU ===\n');
fprintf('%-25s %8s %8s %8s\n', 'Yöntem', 'SNR (dB)', 'RMS (mV)', 'MF (Hz)');
fprintf('%s\n', repmat('-', 55, 1));
metrik_list = {m_ham, m_bw, m_wv, m_chain};
isim_list   = {'Ham Sinyal', 'Butterworth', 'Wavelet', 'BP+Notch Zincir'};
for i = 1:4
    fprintf('%-25s %8.2f %8.4f %8.1f\n', ...
            isim_list{i}, metrik_list{i}.SNR_dB, ...
            metrik_list{i}.RMS, metrik_list{i}.MF_Hz);
end
fprintf('\n');

% =========================================================================
% DEMO 4: velocity_to_angle — Jiroskop Verisi Simülasyonu
% =========================================================================
fprintf('--- DEMO 4: Açısal Hız → Açı Dönüşümü ---\n');

fs_imu = 200;       % IMU tipik örnekleme frekansı
dur_imu = 10;       % 10 saniye
t_imu   = (0:round(fs_imu*dur_imu)-1)' / fs_imu;

% Simüle edilmiş jiroskop verisi:
% Gerçek hareket: 30°/s sabit dönüş + sinüsoidal salınım
gyro_sim = 30 * ones(size(t_imu)) + ...   % Sabit dönüş
           15 * sin(2*pi*0.5*t_imu) + ... % 0.5 Hz salınım
           2  * randn(size(t_imu)) + ...   % Beyaz gürültü
           0.5 * t_imu;                    % Yapay drift (linear)

[ang_deg, ang_rad, t_ang] = velocity_to_angle(gyro_sim, fs_imu, ...
                                               'HPF_fc', 0.05, ...
                                               'Verbose', true);

figure('Name', 'Demo 4: Jiroskop → Açı', 'NumberTitle', 'off', ...
       'Position', [50 50 1000 500]);

subplot(2,1,1);
plot(t_imu, gyro_sim, 'b', 'LineWidth', 1);
title('Simüle Edilmiş Jiroskop Verisi (Drift + Gürültü)');
xlabel('Zaman (s)'); ylabel('Açısal Hız (°/s)');
grid on;

subplot(2,1,2);
plot(t_ang, ang_deg, 'r', 'LineWidth', 1.2);
title('Drift Düzeltilmiş Açı');
xlabel('Zaman (s)'); ylabel('Açı (°)');
grid on;

fprintf('velocity_to_angle testi tamamlandı.\n\n');

% =========================================================================
% DEMO 5: Uygulamayı Aç
% =========================================================================
fprintf('--- DEMO 5: Uygulamayı Açma ---\n');
fprintf('Aşağıdaki komutu çalıştırarak GUI uygulamasını açabilirsiniz:\n');
fprintf('  >> DelsysNoiseMaster\n\n');

cevap = input('Uygulama şimdi açılsın mı? (e/h): ', 's');
if strcmpi(strtrim(cevap), 'e')
    DelsysNoiseMaster;
else
    fprintf('Demo tamamlandı. Uygulamayı açmak için >> DelsysNoiseMaster yazın.\n');
end
