function metrics = compute_metrics(signal, fs, ref_signal)
% =========================================================================
% COMPUTE_METRICS  —  EMG Sinyal Kalite Metrikleri
% =========================================================================
%
% AÇIKLAMA:
%   EMG ve genel biyomedikal sinyaller için temel sinyal kalite
%   metriklerini hesaplar:
%     - SNR   : Signal-to-Noise Ratio (dB)
%     - RMS   : Root Mean Square genlik (mV)
%     - MF    : Median Frequency — medyan frekans (Hz)
%     - MNF   : Mean Frequency — ortalama frekans (Hz)
%     - ARV   : Average Rectified Value — ortalama doğrultulmuş değer
%     - ZCR   : Zero Crossing Rate — sıfır geçiş oranı (Hz)
%     - Kurtosis, Skewness: istatistiksel dağılım metrikleri
%
% GİRİŞLER:
%   signal     : Analiz edilecek sinyal [N×1 double]
%   fs         : Örnekleme frekansı [Hz]
%   ref_signal : (opsiyonel) Referans/temiz sinyal — SNR için
%                Verilmezse SNR hesaplanamaz (NaN döner)
%
% ÇIKIŞLAR:
%   metrics    : Struct, alanlar:
%     .SNR_dB       : Signal-to-Noise Ratio [dB]
%     .RMS          : Root Mean Square [mV]
%     .ARV          : Average Rectified Value [mV]
%     .MF_Hz        : Median Frequency [Hz]
%     .MNF_Hz       : Mean Frequency [Hz]
%     .ZCR_Hz       : Zero Crossing Rate [Hz]
%     .Kurtosis     : 4. moment / varyans^2 (boyutsuz)
%     .Skewness     : 3. moment / std^3 (boyutsuz)
%     .Variance     : Varyans [mV²]
%     .PeakAmplitude: Tepe genlik [mV]
%
% KULLANIM:
%   m = compute_metrics(ham_emg, 2000, temiz_emg);
%   fprintf('SNR=%.2f dB | RMS=%.4f mV | MF=%.1f Hz\n', m.SNR_dB, m.RMS, m.MF_Hz);
%
%   % Sadece gürültülü sinyal (SNR hesaplanmaz):
%   m = compute_metrics(noisy_signal, 2000);
%
% =========================================================================

% Giriş doğrulama
validateattributes(signal, {'double','single'}, {'vector'}, 'compute_metrics', 'signal');
validateattributes(fs,     {'numeric'}, {'scalar','positive'}, 'compute_metrics', 'fs');

signal = double(signal(:));
N = length(signal);

% Referans sinyal opsiyonel
if nargin < 3 || isempty(ref_signal)
    ref_signal = [];
else
    ref_signal = double(ref_signal(:));
    if length(ref_signal) ~= N
        warning('[compute_metrics] ref_signal uzunluğu uyuşmuyor, SNR hesaplanamıyor.');
        ref_signal = [];
    end
end

% =========================================================================
% 1) SNR — Signal-to-Noise Ratio
% =========================================================================
% Tanım: SNR = 10 * log10( P_sinyal / P_gürültü )
%
% Eğer referans sinyal verilmişse:
%   gürültü = sinyal - referans
% Verilmemişse NaN döner.

if ~isempty(ref_signal)
    noise_component = signal - ref_signal;
    P_signal = mean(ref_signal.^2);
    P_noise  = mean(noise_component.^2);
    if P_noise > eps
        metrics.SNR_dB = 10 * log10(P_signal / P_noise);
    else
        metrics.SNR_dB = Inf;  % Sıfır gürültü
    end
else
    metrics.SNR_dB = NaN;  % Referans yok
end

% =========================================================================
% 2) RMS — Root Mean Square
% =========================================================================
% Kas kuvvetiyle doğrudan ilişkilidir. Standart EMG genlik metriği.
metrics.RMS = sqrt(mean(signal.^2));

% =========================================================================
% 3) ARV — Average Rectified Value
% =========================================================================
% Tam dalga doğrultulmuş sinyalin ortalaması. Klinik uygulamalarda yaygın.
metrics.ARV = mean(abs(signal));

% =========================================================================
% 4) MF — Median Frequency (Medyan Frekans)
% =========================================================================
% Güç spektrumunu iki eşit parçaya bölen frekans.
% Kas yorgunluğu ile düşer → yorgunluk göstergesi olarak kullanılır.

win = min(round(N/4), 1024);
[pxx, f] = pwelch(signal, win, [], [], fs);

cumpower = cumsum(pxx);
half_pow = cumpower(end) / 2;
idx_mf   = find(cumpower >= half_pow, 1, 'first');
if isempty(idx_mf)
    metrics.MF_Hz = NaN;
else
    metrics.MF_Hz = f(idx_mf);
end

% =========================================================================
% 5) MNF — Mean Frequency (Ortalama Frekans)
% =========================================================================
% Ağırlıklı ortalama frekans. Spektral dağılımın merkezini gösterir.
% MNF = sum(f * P(f)) / sum(P(f))

metrics.MNF_Hz = sum(f .* pxx) / sum(pxx);

% =========================================================================
% 6) ZCR — Zero Crossing Rate (Sıfır Geçiş Oranı)
% =========================================================================
% Sinyalin sıfırı kaç kez geçtiği per saniye.
% EMG frekans içeriğiyle orantılıdır (yüksek ZCR → yüksek frekans bileşeni).

zero_crossings = sum(abs(diff(sign(signal))) > 0);
metrics.ZCR_Hz = zero_crossings / (N / fs);  % Hz cinsinden (geçiş/saniye)

% =========================================================================
% 7) İstatistiksel Metrikler
% =========================================================================
metrics.Variance     = var(signal);
metrics.Kurtosis     = kurtosis(signal);   % Normal dağılım = 3
metrics.Skewness     = skewness(signal);   % Simetrik = 0
metrics.PeakAmplitude = max(abs(signal));

% =========================================================================
% Sonuçları yazdır
% =========================================================================
fprintf('\n===== SINYAL METRİKLERİ =====\n');
if ~isnan(metrics.SNR_dB)
    fprintf('  SNR              : %.2f dB\n', metrics.SNR_dB);
else
    fprintf('  SNR              : (referans sinyal gerekli)\n');
end
fprintf('  RMS              : %.4f mV\n',  metrics.RMS);
fprintf('  ARV              : %.4f mV\n',  metrics.ARV);
fprintf('  Median Freq (MF) : %.1f Hz\n',  metrics.MF_Hz);
fprintf('  Mean Freq  (MNF) : %.1f Hz\n',  metrics.MNF_Hz);
fprintf('  Zero Cross Rate  : %.1f Hz\n',  metrics.ZCR_Hz);
fprintf('  Kurtosis         : %.3f\n',     metrics.Kurtosis);
fprintf('  Skewness         : %.3f\n',     metrics.Skewness);
fprintf('  Tepe Genlik      : %.4f mV\n',  metrics.PeakAmplitude);
fprintf('=============================\n\n');

end  % function
