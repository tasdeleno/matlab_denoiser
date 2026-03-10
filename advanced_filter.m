function filtered = advanced_filter(signal, fs, filter_type, params)
% =========================================================================
% ADVANCED_FILTER  —  Gelişmiş EMG Filtre Fonksiyonu
% =========================================================================
%
% AÇIKLAMA:
%   EMG ve genel biyomedikal sinyaller için üç farklı filtreleme yöntemi
%   sunar. Her yöntem fizyolojik sinyal işlemede yaygın olarak kullanılır.
%
% GİRİŞLER:
%   signal      : Ham sinyal [N×1 veya N×M double]
%   fs          : Örnekleme frekansı [Hz]
%   filter_type : Filtre tipi string:
%                   'butterworth' — Bant geçiren Butterworth filtresi
%                   'lowpass'     — Alçak geçiren Butterworth filtresi
%                   'notch'       — Çentik (Notch) filtresi
%                   'wavelet'     — Wavelet gürültü giderme
%   params      : Struct — filtre parametreleri (tiplerine göre aşağıda)
%
%   BUTTERWORTH params alanları:
%     params.low   : Alt kesme frekansı [Hz] (varsayılan: 20)
%     params.high  : Üst kesme frekansı [Hz] (varsayılan: 450)
%     params.order : Filtre mertebesi    (varsayılan: 4)
%
%   LOWPASS params alanları:
%     params.cutoff : Kesme frekansı [Hz] (varsayılan: 10)
%     params.order  : Filtre mertebesi    (varsayılan: 4)
%     Kullanım: IMU GYRO envelope (10 Hz), EMG rectified envelope (10 Hz)
%
%   NOTCH params alanları:
%     params.f_notch : Çentik frekansı [Hz] (varsayılan: 50)
%     params.Q       : Kalite faktörü  (varsayılan: 35)
%                      Yüksek Q → daha dar bant
%
%   WAVELET params alanları:
%     params.wavelet : Wavelet ailesi string (varsayılan: 'db4')
%                      Seçenekler: 'db4','db6','sym4','sym6','coif3','bior3.5'
%     params.level   : Ayrışım seviyesi (varsayılan: 5)
%
% ÇIKIŞLAR:
%   filtered : Filtrelenmiş sinyal [N×1 double]
%
% KULLANIM:
%   % Butterworth bandpass (20-450 Hz)
%   p = struct('low',20,'high',450,'order',4);
%   y = advanced_filter(emg, 2000, 'butterworth', p);
%
%   % Notch 50 Hz
%   p = struct('f_notch',50,'Q',35);
%   y = advanced_filter(emg, 2000, 'notch', p);
%
%   % Wavelet denoising
%   p = struct('wavelet','db4','level',5);
%   y = advanced_filter(emg, 2000, 'wavelet', p);
%
% GEREKSİNİMLER:
%   Signal Processing Toolbox (butter, filtfilt, iirnotch)
%   Wavelet Toolbox (wdenoise) — sadece wavelet modu için
%
% =========================================================================

% Girişleri doğrula
validateattributes(signal, {'double','single'}, {'vector'}, 'advanced_filter', 'signal');
validateattributes(fs, {'numeric'}, {'scalar','positive'}, 'advanced_filter', 'fs');

% Sütun vektörüne çevir
signal = double(signal(:));
N = length(signal);

% Varsayılan params
if nargin < 4 || isempty(params)
    params = struct();
end

% =========================================================================
switch lower(strtrim(filter_type))

    % =====================================================================
    % YÖNTEM 1: BUTTERWORTH BANT GEÇİREN FİLTRE
    % =====================================================================
    case 'butterworth'
        % Parametreleri al veya varsayılanı kullan
        fc_low  = get_param(params, 'low',   20);
        fc_high = get_param(params, 'high', 450);
        order   = get_param(params, 'order',  4);

        % Frekans sınırlarını kontrol et
        nyq = fs / 2;  % Nyquist frekansı
        fc_low  = max(0.5,  min(fc_low,  nyq * 0.95));
        fc_high = max(fc_low + 1, min(fc_high, nyq * 0.99));

        % Normalize edilmiş frekanslar (0-1 arası, 1 = Nyquist)
        Wn = [fc_low, fc_high] / nyq;

        % Butterworth bandpass filtresi tasarımı
        % filtfilt: sıfır-faz filtre (gecikme yok, hem ileri hem geri)
        [b, a] = butter(order, Wn, 'bandpass');
        filtered = filtfilt(b, a, signal);

        fprintf('[advanced_filter] Butterworth bandpass: %.0f-%.0f Hz | Mertebe: %d\n', ...
                fc_low, fc_high, order);

    % =====================================================================
    % YÖNTEM 2: NOTCH (ÇENTİK) FİLTRE — 50/60 Hz Şebeke Gürültüsü
    % =====================================================================
    case 'notch'
        f_notch = get_param(params, 'f_notch', 50);
        Q       = get_param(params, 'Q',       35);

        nyq = fs / 2;

        % Tek notch filtresi: hedef frekans
        Wo = f_notch / nyq;  % Normalize edilmiş frekans
        if Wo >= 1
            warning('Notch frekansı Nyquist limitini aşıyor. f_notch=%g Hz, fs=%g Hz', ...
                    f_notch, fs);
            filtered = signal;
            return;
        end

        % IIR notch filtresi tasarımı (iirnotch: 2. mertebe)
        bw = Wo / Q;  % Bant genişliği = frekans / Q
        [b, a] = iirnotch(Wo, bw);
        filtered = filtfilt(b, a, signal);

        % İsteğe bağlı: harmonikleri de temizle (100, 150, 200 Hz...)
        harmonics = 2:floor(nyq / f_notch);
        for k = harmonics
            f_harm = k * f_notch;
            if f_harm >= nyq * 0.99, break; end
            Wo_h = f_harm / nyq;
            bw_h = Wo_h / (Q * k);  % Harmoniklerde bant daha dar
            [bh, ah] = iirnotch(Wo_h, bw_h);
            filtered = filtfilt(bh, ah, filtered);
        end

        fprintf('[advanced_filter] Notch: %.0f Hz | Q=%.0f | %d harmonik temizlendi\n', ...
                f_notch, Q, length(harmonics));

    % =====================================================================
    % YÖNTEM 3: WAVELET GÜRÜLTÜ GİDERME
    % =====================================================================
    case 'wavelet'
        wname = get_param(params, 'wavelet', 'db4');
        level = get_param(params, 'level',    5);

        % wdenoise: Wavelet Toolbox fonksiyonu
        % SURE (Stein's Unbiased Risk Estimate) eşiği kullanır
        % Bu, gürültü giderme için optimal bir eşik seçim yöntemidir.
        try
            % wdenoise(X, N, 'Wavelet', W) :
            %   X     = sinyal
            %   N     = ayrışım seviyesi
            %   W     = wavelet ailesi
            filtered = wdenoise(signal, level, 'Wavelet', wname);
            filtered = filtered(:);  % Sütun vektörü garantisi

            fprintf('[advanced_filter] Wavelet (%s) | Seviye: %d | wdenoise SURE eşiği\n', ...
                    wname, level);
        catch ME
            % Wavelet Toolbox yoksa veya başka hata
            error('[advanced_filter] Wavelet modu başarısız: %s\nWavelet Toolbox yüklü mü?', ...
                  ME.message);
        end

    % =====================================================================
    % YÖNTEM 4: ALÇAK GEÇİREN (LOW-PASS) BUTTERWORTH
    % =====================================================================
    % Kullanım alanları:
    %   • IMU GYRO sinyali: yavaş hareketlerde >10 Hz gürültü kesilir
    %   • EMG tam-dalga rectification sonrası envelope çıkarma (10 Hz)
    case 'lowpass'
        cutoff = get_param(params, 'cutoff', 10);
        order  = get_param(params, 'order',   4);

        nyq = fs / 2;
        Wn  = max(0.001, min(cutoff / nyq, 0.999));   % 0<Wn<1 zorunlu

        [b, a] = butter(order, Wn, 'low');
        filtered = filtfilt(b, a, signal);

        fprintf('[advanced_filter] Low-pass: %.1f Hz | Mertebe: %d\n', cutoff, order);

    otherwise
        error('[advanced_filter] Bilinmeyen filtre tipi: "%s"\nGeçerli tipler: butterworth, lowpass, notch, wavelet', ...
              filter_type);
end  % switch

% Son kontrol: çıkış sütun vektörü ve NaN içermemeli
filtered = filtered(:);
if any(isnan(filtered)) || any(isinf(filtered))
    warning('[advanced_filter] Filtrelenmiş sinyal NaN/Inf içeriyor. Ham sinyal döndürülüyor.');
    filtered = signal;
end

end  % main function


% =========================================================================
% YARDIMCI: get_param — Struct'tan güvenli değer okuma
% =========================================================================
function val = get_param(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end
