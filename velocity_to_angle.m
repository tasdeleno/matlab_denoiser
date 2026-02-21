function [angle_deg, angle_rad, t_out] = velocity_to_angle(gyro_data, fs, varargin)
% =========================================================================
% VELOCITY_TO_ANGLE  —  Açısal Hız → Açı Dönüştürücü (Drift Düzeltmeli)
% =========================================================================
%
% AÇIKLAMA:
%   Delsys IMU/Gyroscope sensöründen gelen açısal hız verisini (°/s veya
%   rad/s) integre ederek açıya (°) dönüştürür. Jiroskopların uzun süreli
%   kullanımında biriken "drift" (sürüklenme) sorununu yüksek geçiren
%   Butterworth filtresiyle düzeltir.
%
%   Yöntem:
%     1) Trapez integrasyon (cumtrapz) ile ham açısal hız → açı
%     2) Yüksek geçiren Butterworth filtresi (drift düzeltme)
%     3) İsteğe bağlı: ölçüm birimi dönüşümü (deg/s ↔ rad/s)
%
% GİRİŞLER:
%   gyro_data   : Açısal hız sinyali [N×1 veya N×3 double]
%                 - N×1: tek eksen (örn. sadece z-ekseni)
%                 - N×3: üç eksen [x, y, z], her eksen ayrı işlenir
%   fs          : Örnekleme frekansı [Hz]
%
%   OPSİYONEL (isim-değer çiftleri):
%   'Unit'      : Giriş birimi: 'deg/s' (varsayılan) veya 'rad/s'
%   'HPF_fc'    : Drift düzeltme yüksek geçiren filtre kesme frekansı [Hz]
%                 (varsayılan: 0.01 Hz)
%   'HPF_order' : Yüksek geçiren filtre mertebesi (varsayılan: 2)
%   'InitAngle' : Başlangıç açısı [derece] (varsayılan: 0)
%   'Verbose'   : true/false — bilgi çıktısı (varsayılan: true)
%
% ÇIKIŞLAR:
%   angle_deg   : Drift düzeltilmiş açı [N×M double, derece]
%   angle_rad   : Drift düzeltilmiş açı [N×M double, radyan]
%   t_out       : Zaman vektörü [N×1 double, saniye]
%
% KULLANIM:
%   % Tek eksen:
%   [ang_deg, ang_rad, t] = velocity_to_angle(gyro_z, 200);
%
%   % Üç eksen, rad/s giriş:
%   [ang_deg, ~, t] = velocity_to_angle(gyro_xyz, 200, ...
%                         'Unit', 'rad/s', 'HPF_fc', 0.02);
%
%   % Görselleştirme:
%   figure;
%   subplot(2,1,1); plot(t, gyro_z); title('Açısal Hız (°/s)');
%   subplot(2,1,2); plot(t, ang_deg); title('Hesaplanan Açı (°)');
%
% NOTLAR:
%   - Drift düzeltme HPF kesme frekansı (HPF_fc) kritiktir:
%       * Çok yüksek → gerçek açı değişimlerini siler
%       * Çok düşük → drift düzeltme yetersiz kalır
%       * 0.01-0.1 Hz arası çoğu hareket analizi için uygundur
%   - Kısa süreli (<1 s) hareketlerde drift ihmal edilebilir
%   - Yüksek hassasiyet gerektiren uygulamalarda accelerometre
%     füzyonu (Complementary/Kalman filtre) önerilir
%
% GEREKSİNİMLER:
%   Signal Processing Toolbox (butter, filtfilt, cumtrapz)
%
% =========================================================================

% ---- Giriş doğrulama ----
validateattributes(gyro_data, {'double','single'}, {'2d','nonempty'}, ...
                   'velocity_to_angle', 'gyro_data');
validateattributes(fs, {'numeric'}, {'scalar','positive'}, ...
                   'velocity_to_angle', 'fs');

% Satır vektörünü sütuna çevir
if isrow(gyro_data), gyro_data = gyro_data'; end
gyro_data = double(gyro_data);

[N, M] = size(gyro_data);  % N: örnek sayısı, M: eksen sayısı

% ---- Opsiyonel argümanlar ----
p = inputParser();
addParameter(p, 'Unit',      'deg/s', @(x) ismember(x, {'deg/s','rad/s'}));
addParameter(p, 'HPF_fc',    0.01,   @(x) isnumeric(x) && x > 0);
addParameter(p, 'HPF_order', 2,      @(x) isnumeric(x) && x >= 1 && x <= 8);
addParameter(p, 'InitAngle', 0,      @isnumeric);
addParameter(p, 'Verbose',   true,   @islogical);
parse(p, varargin{:});
opt = p.Results;

% ---- Zaman vektörü ----
t_out = (0:N-1)' / fs;  % Saniye cinsinden

% =========================================================================
% ADIM 1: Birim Dönüşümü
% =========================================================================
% Hesaplama deg cinsinden yapılır, sonunda rad'a dönüştürülür
if strcmp(opt.Unit, 'rad/s')
    % rad/s → deg/s
    gyro_degs = gyro_data * (180 / pi);
    if opt.Verbose
        fprintf('[velocity_to_angle] Birim dönüşümü: rad/s → deg/s\n');
    end
else
    gyro_degs = gyro_data;  % Zaten deg/s
end

% =========================================================================
% ADIM 2: Trapez İntegrasyon (cumtrapz)
% =========================================================================
% cumtrapz(t, y): t vektörüne göre y'yi trapez yöntemiyle kümülatif integre eder
% Sonuç: açı değişimi [derece]
%
% Neden cumtrapz ve basit cumsum değil?
%   cumtrapz değişken örnekleme aralıklarında daha doğrudur ve
%   trapez yöntemi orta nokta kuralından daha az hata içerir.

angle_raw = cumtrapz(t_out, gyro_degs);  % [N×M, derece]

% Başlangıç açısını ekle
for col = 1:M
    angle_raw(:, col) = angle_raw(:, col) + opt.InitAngle;
end

% =========================================================================
% ADIM 3: Drift Düzeltme — Yüksek Geçiren Filtre
% =========================================================================
% Jiroskop drift'i düşük frekanslı bir sinyal olarak modellenir.
% Yüksek geçiren filtre (HPF) bu yavaş sürüklenmeyi sinyalden çıkarır.
%
% Tasarım:
%   - Butterworth HPF: maximally flat (düz geçiş bandı)
%   - filtfilt: sıfır-faz (gecikme yok)
%   - fc = HPF_fc: genellikle 0.01-0.1 Hz

nyq    = fs / 2;
hpf_fc = opt.HPF_fc;

% Kesme frekansı kontrolü
if hpf_fc >= nyq
    warning('[velocity_to_angle] HPF_fc (%g Hz) >= Nyquist (%g Hz). Drift düzeltme atlandı.', ...
            hpf_fc, nyq);
    angle_corrected = angle_raw;
else
    Wn_hp = hpf_fc / nyq;  % Normalize edilmiş kesme frekansı

    % Yüksek geçiren Butterworth filtre katsayıları
    [b_hp, a_hp] = butter(opt.HPF_order, Wn_hp, 'high');

    angle_corrected = zeros(N, M);
    for col = 1:M
        % filtfilt: iki geçişli filtreleme → sıfır faz gecikmesi
        angle_corrected(:, col) = filtfilt(b_hp, a_hp, angle_raw(:, col));
    end

    if opt.Verbose
        fprintf('[velocity_to_angle] Drift düzeltme HPF: fc=%.4f Hz | Mertebe=%d\n', ...
                hpf_fc, opt.HPF_order);
    end
end

% =========================================================================
% ADIM 4: Çıkışları hazırla
% =========================================================================
angle_deg = angle_corrected;                   % [derece]
angle_rad = angle_corrected * (pi / 180);     % [radyan]

% ---- Bilgi çıktısı ----
if opt.Verbose
    fprintf('[velocity_to_angle] İşlem tamamlandı:\n');
    fprintf('  Fs=%.0f Hz | N=%d örnek | %d eksen | Süre=%.2f s\n', ...
            fs, N, M, N/fs);
    for col = 1:M
        raw_drift  = angle_raw(end, col) - angle_raw(1, col);
        corr_range = max(angle_corrected(:,col)) - min(angle_corrected(:,col));
        fprintf('  Eksen %d: Ham toplam değişim=%.2f° | Düzeltilmiş aralık=%.2f°\n', ...
                col, raw_drift, corr_range);
    end
end

end  % function
