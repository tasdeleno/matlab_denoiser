function imu_emg_multisensor_analiz(mat_file, egzersiz_adi)
% IMU_EMG_MULTISENSOR_ANALIZ  Skolyoz tedavi egzersizleri için çok sensörlü
%   IMU+EMG analizi. 6 IMU (tamamlayıcı filtre: ACC+GYRO) + 6 EMG kanalını
%   aynı anda işler, tek figure'da 12 subplot ile gösterir.
%
% Kullanım:
%   imu_emg_multisensor_analiz                        % dosya seçici
%   imu_emg_multisensor_analiz('kayit.mat')
%   imu_emg_multisensor_analiz('kayit.mat', 'T8-T9 Lateral Fleksiyon')
%
% Bağımlılıklar (aynı klasörde olmalı):
%   advanced_filter.m   – EMG bandpass + notch
%   compute_metrics.m   – EMG metrikleri (RMS, SNR, MF)
%
% Referans:
%   "Intelligent Monitoring System for Scoliosis Treatment Exercises
%    Using IMU and EMG Sensors" (PDF direktifleri)
%
% Delsys Trigno Avanti eksen sözleşmesi (sensör sırta düz):
%   ACC.X → ön-arka (anterior+), ACC.Y → lateral (sağ+), ACC.Z → yukarı+
%   GYRO.X → lateral eğilme (roll), GYRO.Y → fleksiyon (pitch),
%   GYRO.Z → eksenel rotasyon (yaw)

% ======================================================================
%% 1. KONFİGÜRASYON  (kullanıcı burada düzenler)
% ======================================================================

% ── Örnekleme frekansları ──────────────────────────────────────────────
IMU_FS = 148.15;    % [Hz] – Delsys Trigno IMU
EMG_FS = 1259.26;   % [Hz] – Delsys Trigno EMG
% NOT: Dosyadan otomatik okunur; bu değerler sadece dosyada Fs yoksa kullanılır.

% ── Tamamlayıcı filtre katsayısı ──────────────────────────────────────
% 0.95–0.98 önerilir. Yüksek α → GYRO'ya daha çok güven (hızlı hareket).
% Düşük α  → ACC'ye daha çok güven (drift daha hızlı düzeltilir).
CF_ALPHA = 0.98;

% ── Başlangıç sıfırlama penceresi (saniye) ────────────────────────────
% Kaydın ilk N saniyesinin ortalaması baseline (sıfır referansı) alınır.
% Kişi kayıt başında nötr duruşta ise 0.5–1.0 s uygun.
BASELINE_DUR = 0.5;  % [s]

% ── EMG filtre parametreleri ──────────────────────────────────────────
EMG_BP_LOW  = 20;    % Bandpass alt sınırı [Hz]
EMG_BP_HIGH = 450;   % Bandpass üst sınırı [Hz]
EMG_BP_ORD  = 4;     % Filtre mertebesi
EMG_NOTCH_F = 50;    % Güç frekansı (Türkiye: 50 Hz; ABD: 60)
EMG_NOTCH_Q = 35;    % Notch Q faktörü

% ── Klinik eşikler (PDF Tablo 10) ─────────────────────────────────────
THR_COMP   = 5;   % Kompensatuar hareket eşiği — tüm sensörler [°]
THR_SST_Z  = [5 25];   % Seated Spinal Twist: T8-T9 Z-rot hedef [°]
THR_SSB_Y  = [5 30];   % Standing Side Bend: T8-T9 Y-lat hedef [°]
THR_WA_SC  = [10 20];  % Wall Angels: skapula X-rot hedef [°]
EMG_ASYM   = 15;  % Sol-sağ EMG asimetri toleransı [%]

% ── IMU sensör tanımları ───────────────────────────────────────────────
% Her satır: {kanal_keyword, etiket, renk}
% keyword: BÜYÜK/küçük harf farksız kanal adı içinde aranır.
% Delsys örnek isimlendirme: "T8T9 Mid-thoracic: GYRO.X"
% Kendi dosyanıza göre keyword'leri düzenleyin.
IMU_DEF = {
    'T1',       'T1-T2  (Üst Torakal)',  [0.20 0.60 0.85];
    'T8',       'T8-T9  (Mid Torakal)',  [0.85 0.30 0.10];
    'L2',       'L2-L3  (Lumbar)',       [0.10 0.70 0.30];
    'Sacrum',   'Sakrum (Pelvis)',        [0.60 0.10 0.80];
    'Scapula.L','Sol Skapula',           [0.90 0.60 0.10];
    'Scapula.R','Sağ Skapula',           [0.30 0.80 0.80];
};

% ── EMG sensör tanımları ───────────────────────────────────────────────
EMG_DEF = {
    'Upper Trapezius.L',  'Sol Trapezius',        [0.20 0.60 0.85];
    'Upper Trapezius.R',  'Sağ Trapezius',        [0.85 0.30 0.10];
    'Latissimus Dorsi.L', 'Sol Latissimus',       [0.10 0.70 0.30];
    'Latissimus Dorsi.R', 'Sağ Latissimus',       [0.60 0.10 0.80];
    'Erector Spinae.L',   'Sol Erector Spinae',   [0.90 0.55 0.10];
    'Erector Spinae.R',   'Sağ Erector Spinae',   [0.30 0.80 0.80];
};

N_IMU = size(IMU_DEF, 1);   % 6
N_EMG = size(EMG_DEF, 1);   % 6

% ======================================================================
%% 2. VERİ YÜKLEME
% ======================================================================

if nargin < 1 || isempty(mat_file)
    [fn, fp] = uigetfile('*.mat', 'Delsys .mat dosyasını seçin');
    if isequal(fn, 0), disp('[iptal] Dosya seçilmedi.'); return; end
    mat_file = fullfile(fp, fn);
end
if nargin < 2 || isempty(egzersiz_adi)
    egzersiz_adi = '';
end

fprintf('\n======================================================\n');
fprintf(' IMU+EMG Çok Sensörlü Analiz\n');
fprintf(' Dosya : %s\n', mat_file);
if ~isempty(egzersiz_adi)
    fprintf(' Egzersiz: %s\n', egzersiz_adi);
end
fprintf('======================================================\n');

raw = load(mat_file);

% Delsys format kontrolü
if ~isfield(raw,'Channels') || ~isfield(raw,'Data') || ~isfield(raw,'Fs')
    error(['Delsys formatı bulunamadı.\n' ...
           'Gerekli değişkenler: Channels, Fs, Data\n' ...
           'Yeniden export: Delsys Lab → File → Export → MATLAB (.mat)\n' ...
           '  "Include Signal Data" seçili olmalı.']);
end

% Kanal meta
ch_names = string(raw.Channels(:));   % N_ch×1 string
fs_arr   = double(raw.Fs(:));         % N_ch×1 Hz
data_mat = double(raw.Data);          % N_ch × N_samples
N_ch     = numel(ch_names);
N_samp   = size(data_mat, 2);

fprintf(' Toplam kanal : %d\n', N_ch);
fprintf(' Örnek sayısı : %d\n', N_samp);
fprintf(' Kanallar listesi:\n');
for k = 1:N_ch
    fprintf('   [%3d] %-45s  Fs=%.2f Hz\n', k, ch_names(k), fs_arr(k));
end
fprintf('\n');

% ======================================================================
%% 3. KANAL EŞLEŞME
% ======================================================================

% --- IMU: her sensör için ACC.X/Y/Z + GYRO.X/Y/Z index'leri bul ------
imu_idx = struct();   % imu_idx(i) = struct ile acc/gyro index'leri
imu_fs  = zeros(N_IMU, 1);

for i = 1:N_IMU
    kw = IMU_DEF{i, 1};  % keyword
    label = IMU_DEF{i, 2};

    % Ana sensörü keyword ile bul
    base_idx = find(contains(ch_names, kw, 'IgnoreCase', true));
    if isempty(base_idx)
        fprintf(' [UYARI] IMU sensörü bulunamadı: "%s" (%s)\n', kw, label);
        imu_idx(i).ok   = false;
        imu_idx(i).accX = []; imu_idx(i).accY = []; imu_idx(i).accZ = [];
        imu_idx(i).gyrX = []; imu_idx(i).gyrY = []; imu_idx(i).gyrZ = [];
        continue
    end

    % ACC ve GYRO eksenleri
    imu_idx(i).ok   = true;
    imu_idx(i).accX = findInSubset(ch_names, base_idx, 'ACC.X');
    imu_idx(i).accY = findInSubset(ch_names, base_idx, 'ACC.Y');
    imu_idx(i).accZ = findInSubset(ch_names, base_idx, 'ACC.Z');
    imu_idx(i).gyrX = findInSubset(ch_names, base_idx, 'GYRO.X');
    imu_idx(i).gyrY = findInSubset(ch_names, base_idx, 'GYRO.Y');
    imu_idx(i).gyrZ = findInSubset(ch_names, base_idx, 'GYRO.Z');

    % Fs: GYRO.X kanalından al
    if ~isempty(imu_idx(i).gyrX)
        imu_fs(i) = fs_arr(imu_idx(i).gyrX(1));
    else
        imu_fs(i) = IMU_FS;
    end

    fprintf(' IMU %d %-25s → ACC:[%s %s %s]  GYRO:[%s %s %s]  Fs=%.2f\n', ...
        i, label, idx2str(imu_idx(i).accX), idx2str(imu_idx(i).accY), ...
        idx2str(imu_idx(i).accZ), idx2str(imu_idx(i).gyrX), ...
        idx2str(imu_idx(i).gyrY), idx2str(imu_idx(i).gyrZ), imu_fs(i));
end

% --- EMG: her kas için kanal index'i bul -------------------------------
emg_idx = zeros(N_EMG, 1);
emg_fs  = zeros(N_EMG, 1);

for i = 1:N_EMG
    kw = EMG_DEF{i, 1};
    label = EMG_DEF{i, 2};
    hits = find(contains(ch_names, kw, 'IgnoreCase', true) & ...
                contains(ch_names, 'EMG',  'IgnoreCase', true));
    if isempty(hits)
        % fallback: sadece keyword ile ara
        hits = find(contains(ch_names, kw, 'IgnoreCase', true));
    end
    if isempty(hits)
        fprintf(' [UYARI] EMG kanalı bulunamadı: "%s" (%s)\n', kw, label);
        emg_idx(i) = 0;
    else
        emg_idx(i) = hits(1);
        emg_fs(i)  = fs_arr(hits(1));
        fprintf(' EMG %d %-25s → kanal %d  Fs=%.2f\n', i, label, hits(1), emg_fs(i));
    end
end
fprintf('\n');

% ======================================================================
%% 4. TAMAMLAYICI FİLTRE — IMU döngüsü
% ======================================================================

imu_angles  = cell(N_IMU, 1);   % {i} = [N×3] [sagital, frontal, rotasyon]°
imu_time    = cell(N_IMU, 1);

fprintf(' [IMU] Tamamlayıcı filtre uygulanıyor...\n');
for i = 1:N_IMU
    label = IMU_DEF{i, 2};
    if ~imu_idx(i).ok
        fprintf('   %-25s → ATLANDI (kanal yok)\n', label);
        imu_angles{i} = [];
        imu_time{i}   = [];
        continue
    end

    fs_i = imu_fs(i);
    if fs_i <= 0, fs_i = IMU_FS; end

    % Kanal verilerini çek ve NaN kırp
    acc  = zeros(N_samp, 3);
    gyro = zeros(N_samp, 3);

    acc(:,1)  = getRow(data_mat, imu_idx(i).accX, N_samp);
    acc(:,2)  = getRow(data_mat, imu_idx(i).accY, N_samp);
    acc(:,3)  = getRow(data_mat, imu_idx(i).accZ, N_samp);
    gyro(:,1) = getRow(data_mat, imu_idx(i).gyrX, N_samp);
    gyro(:,2) = getRow(data_mat, imu_idx(i).gyrY, N_samp);
    gyro(:,3) = getRow(data_mat, imu_idx(i).gyrZ, N_samp);

    % Geçerli örnek sayısını bul (sondaki NaN'ları kırp)
    valid = find(~any(isnan([acc gyro]), 2), 1, 'last');
    if isempty(valid) || valid < 10
        fprintf('   %-25s → ATLANDI (geçerli veri < 10 örnek)\n', label);
        imu_angles{i} = []; imu_time{i} = []; continue
    end
    acc  = acc(1:valid,  :);
    gyro = gyro(1:valid, :);

    t_i = (0:valid-1)' / fs_i;
    imu_time{i} = t_i;

    % Tamamlayıcı filtre
    angle_cf = complementary_filter(acc, gyro, fs_i, CF_ALPHA);

    % Baseline sıfırlama
    n_base = max(1, round(BASELINE_DUR * fs_i));
    baseline = mean(angle_cf(1:n_base, :), 1);
    angle_cf = angle_cf - baseline;

    imu_angles{i} = angle_cf;  % [valid×3]: sütun1=sagital, 2=frontal, 3=rotasyon
    fprintf('   %-25s → %d örnek | %.1f s | Fs=%.2f Hz\n', ...
        label, valid, valid/fs_i, fs_i);
end

% ======================================================================
%% 5. EMG FİLTRELEME + METRİKLER
% ======================================================================

emg_raw_cell  = cell(N_EMG, 1);
emg_filt_cell = cell(N_EMG, 1);
emg_met_cell  = cell(N_EMG, 1);
emg_time_cell = cell(N_EMG, 1);

fprintf('\n [EMG] Filtreleme + metrikler...\n');

params_bp = struct('low', EMG_BP_LOW, 'high', EMG_BP_HIGH, 'order', EMG_BP_ORD);
params_n  = struct('f_notch', EMG_NOTCH_F, 'Q', EMG_NOTCH_Q);

for i = 1:N_EMG
    label = EMG_DEF{i, 2};
    if emg_idx(i) == 0
        fprintf('   %-25s → ATLANDI\n', label);
        continue
    end

    raw_full = data_mat(emg_idx(i), :)';   % N_samp×1
    valid = find(~isnan(raw_full), 1, 'last');
    if isempty(valid) || valid < 20
        fprintf('   %-25s → ATLANDI (geçerli veri yok)\n', label);
        continue
    end
    raw_v = raw_full(1:valid);
    fs_e  = emg_fs(i); if fs_e <= 0, fs_e = EMG_FS; end

    % Filtre
    try
        filt_v = advanced_filter(raw_v, fs_e, 'butterworth', params_bp);
        filt_v = advanced_filter(filt_v, fs_e, 'notch',      params_n);
    catch err
        fprintf('   [UYARI] Filtre hatası (%s): %s\n', label, err.message);
        filt_v = raw_v;
    end

    % Metrikler
    try
        met = compute_metrics(filt_v, fs_e, raw_v);
    catch
        met = struct('RMS', rms(filt_v), 'MF_Hz', 0, 'SNR_dB', NaN);
    end

    emg_raw_cell{i}  = raw_v;
    emg_filt_cell{i} = filt_v;
    emg_met_cell{i}  = met;
    emg_time_cell{i} = (0:valid-1)' / fs_e;

    fprintf('   %-25s → %d örnek | RMS_filt=%.4f | SNR=%.1f dB | MF=%.1f Hz\n', ...
        label, valid, met.RMS, met.SNR_dB, met.MF_Hz);
end

% ======================================================================
%% 6. GRAFİKLER
% ======================================================================

fig = figure('Name', 'Çok Sensörlü IMU+EMG Analizi', ...
    'Position', [30, 30, 1700, 940], 'Color', [0.12 0.12 0.15]);

tiledOpts = {'TileSpacing','compact','Padding','compact'};
tl = tiledlayout(fig, 4, 3, tiledOpts{:});

% Genel başlık
[~, fn_short, ext] = fileparts(mat_file);
titletxt = sprintf('IMU+EMG Çok Sensörlü Analiz  —  %s%s', fn_short, ext);
if ~isempty(egzersiz_adi)
    titletxt = [titletxt, '  |  ', egzersiz_adi];
end
title(tl, titletxt, 'FontSize', 13, 'FontWeight', 'bold', 'Color', [0.9 0.9 0.9]);

% Eksen rengi şeması
ax_col   = [0.18 0.18 0.22];   % subplot arka planı
txt_col  = [0.85 0.85 0.85];   % metin rengi
grid_col = [0.28 0.28 0.33];   % grid çizgisi

imu_axis_col = {[0.95 0.25 0.25], [0.25 0.55 0.95], [0.25 0.85 0.45]};  % X=kırm, Y=mavi, Z=yeşil
imu_axis_lbl = {'X-Sagital(flex)', 'Y-Frontal(lat)', 'Z-Rotasyon(yaw)'};

% ── IMU subplot'ları (tile 1–6) ────────────────────────────────────────
for i = 1:N_IMU
    ax = nexttile(tl);
    set(ax, 'Color', ax_col, 'XColor', txt_col, 'YColor', txt_col, ...
        'GridColor', grid_col, 'MinorGridColor', grid_col, ...
        'FontSize', 8, 'Box', 'on');
    grid(ax, 'on'); hold(ax, 'on');

    label = IMU_DEF{i, 2};
    col_s = IMU_DEF{i, 3};   % sensör rengi (legend'de sensör ismi için)

    if isempty(imu_angles{i})
        text(ax, 0.5, 0.5, sprintf('Kanal bulunamadı\n(%s)', IMU_DEF{i,1}), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'Color',[0.6 0.6 0.6],'FontSize',9,'Parent',ax);
        title(ax, label, 'Color', col_s, 'FontSize', 9, 'FontWeight','bold');
        continue
    end

    t_i  = imu_time{i};
    ang  = imu_angles{i};   % N×3

    % ±5° kompensasyon eşiği
    yline(ax,  THR_COMP, '--', 'Color',[0.95 0.45 0.15], ...
        'LineWidth',1.2, 'Alpha',0.8, 'HandleVisibility','off');
    yline(ax, -THR_COMP, '--', 'Color',[0.95 0.45 0.15], ...
        'LineWidth',1.2, 'Alpha',0.8, 'HandleVisibility','off');

    % 3 eksen çizgisi
    hl = gobjects(3,1);
    for ax_k = 1:3
        hl(ax_k) = plot(ax, t_i, ang(:, ax_k), ...
            'Color', imu_axis_col{ax_k}, 'LineWidth', 0.9);
    end

    % Maks değer annotasyonu
    [mx_val, mx_idx] = max(abs(ang(:)));
    [mx_r, mx_c] = ind2sub(size(ang), mx_idx);
    mx_str = sprintf('|MAX|=%.1f°', abs(ang(mx_r, mx_c)));
    text(ax, t_i(mx_r), ang(mx_r, mx_c), ['↑ ' mx_str], ...
        'Color', imu_axis_col{mx_c}, 'FontSize', 7.5, 'VerticalAlignment','bottom');

    % Eşik aşımı süresi (her eksen)
    dt = 1 / imu_fs(i);
    for ax_k = 1:3
        n_over = sum(abs(ang(:, ax_k)) > THR_COMP);
        if n_over > 0
            t_over = n_over * dt;
            text(ax, t_i(end)*0.02, -THR_COMP - 3 - (ax_k-1)*3, ...
                sprintf('%s: %.1fs >%d°', imu_axis_lbl{ax_k}(1), t_over, THR_COMP), ...
                'Color', imu_axis_col{ax_k}, 'FontSize', 7);
        end
    end

    legend(ax, hl, imu_axis_lbl, 'TextColor', txt_col, 'Color', ax_col, ...
        'FontSize', 7, 'Location', 'northeast', 'Box','off');
    xlabel(ax, 'Zaman (s)', 'Color', txt_col, 'FontSize', 8);
    ylabel(ax, 'Açı (°)',   'Color', txt_col, 'FontSize', 8);
    title(ax, label, 'Color', col_s, 'FontSize', 9, 'FontWeight','bold');
    yline(ax, 0, '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.7, 'HandleVisibility','off');
end

% ── EMG subplot'ları (tile 7–12) ──────────────────────────────────────
for i = 1:N_EMG
    ax = nexttile(tl);
    set(ax, 'Color', ax_col, 'XColor', txt_col, 'YColor', txt_col, ...
        'GridColor', grid_col, 'FontSize', 8, 'Box', 'on');
    grid(ax, 'on'); hold(ax, 'on');

    label = EMG_DEF{i, 2};
    col_s = EMG_DEF{i, 3};

    if isempty(emg_filt_cell{i})
        text(ax, 0.5, 0.5, sprintf('Kanal bulunamadı\n(%s)', EMG_DEF{i,1}), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'Color',[0.6 0.6 0.6],'FontSize',9,'Parent',ax);
        title(ax, label, 'Color', col_s, 'FontSize', 9, 'FontWeight','bold');
        continue
    end

    t_e      = emg_time_cell{i};
    raw_v    = emg_raw_cell{i};
    filt_v   = emg_filt_cell{i};
    met      = emg_met_cell{i};

    % Ham sinyal (gri, arka planda)
    plot(ax, t_e, raw_v,  'Color', [0.5 0.5 0.5 0.35], 'LineWidth', 0.5);
    % Filtrelenmiş sinyal (renkli, ön)
    plot(ax, t_e, filt_v, 'Color', col_s, 'LineWidth', 0.9);

    % Metrik kutusu (sağ üst köşe)
    snr_str = '';
    if isfield(met,'SNR_dB') && isfinite(met.SNR_dB)
        snr_str = sprintf(' | SNR=%.1fdB', met.SNR_dB);
    end
    mf_str = '';
    if isfield(met,'MF_Hz') && met.MF_Hz > 0
        mf_str = sprintf(' | MF=%.0fHz', met.MF_Hz);
    end
    ann_str = sprintf('RMS=%.4f mV%s%s', met.RMS, snr_str, mf_str);
    text(ax, t_e(end)*0.99, max(filt_v)*0.92, ann_str, ...
        'HorizontalAlignment','right','FontSize',7,'Color',col_s, ...
        'BackgroundColor',[ax_col 0.6]);

    legend(ax, {'Ham','Filtrelenmiş'}, 'TextColor', txt_col, 'Color', ax_col, ...
        'FontSize', 7, 'Location', 'northwest', 'Box','off');
    xlabel(ax, 'Zaman (s)',   'Color', txt_col, 'FontSize', 8);
    ylabel(ax, 'Amplitüd (mV)', 'Color', txt_col, 'FontSize', 8);
    title(ax, label, 'Color', col_s, 'FontSize', 9, 'FontWeight','bold');
end

% ── Ortak başlık çubuğu: eşik açıklaması ─────────────────────────────
annotation(fig,'textbox',[0.01 0.01 0.99 0.025], ...
    'String', sprintf(['± %.0f° kesikli turuncu = kompensasyon eşiği  |  ' ...
                       'Tamamlayıcı filtre α=%.2f  |  ' ...
                       'EMG: Butterworth BP %d–%d Hz + Notch %d Hz'], ...
                       THR_COMP, CF_ALPHA, EMG_BP_LOW, EMG_BP_HIGH, EMG_NOTCH_F), ...
    'FitBoxToText','off','EdgeColor','none', ...
    'Color',[0.6 0.6 0.6],'FontSize',8,'BackgroundColor','none');

% ======================================================================
%% 7. ÖZET TABLO (konsol)
% ======================================================================

fprintf('\n======================================================\n');
fprintf(' ÖZET — IMU Açı Maks. Değerleri\n');
fprintf('======================================================\n');
fprintf(' %-25s  %8s  %8s  %8s  %10s\n', ...
    'Sensör', 'Maks X(°)', 'Maks Y(°)', 'Maks Z(°)', 'Eşik Aşımı');
fprintf(' %s\n', repmat('-', 1, 70));
for i = 1:N_IMU
    label = IMU_DEF{i, 2};
    if isempty(imu_angles{i})
        fprintf(' %-25s  %8s  %8s  %8s  %10s\n', label,'—','—','—','—');
        continue
    end
    ang = imu_angles{i};
    mx  = max(abs(ang), [], 1);
    any_over = sum(max(abs(ang), [], 2) > THR_COMP);
    dt  = 1 / imu_fs(i);
    t_over_str = sprintf('%.1f s', any_over * dt);
    if any_over == 0, t_over_str = 'YOK'; end
    fprintf(' %-25s  %8.2f  %8.2f  %8.2f  %10s\n', ...
        label, mx(1), mx(2), mx(3), t_over_str);
end

fprintf('\n======================================================\n');
fprintf(' ÖZET — EMG Metrikleri\n');
fprintf('======================================================\n');
fprintf(' %-25s  %10s  %10s  %8s  %10s\n', ...
    'Kas', 'RMS(ham)', 'RMS(filt)', 'SNR(dB)', 'MF(Hz)');
fprintf(' %s\n', repmat('-', 1, 70));
for i = 1:N_EMG
    label = EMG_DEF{i, 2};
    if isempty(emg_filt_cell{i})
        fprintf(' %-25s  %10s  %10s  %8s  %10s\n', label,'—','—','—','—');
        continue
    end
    rms_raw  = rms(emg_raw_cell{i});
    rms_filt = rms(emg_filt_cell{i});
    met      = emg_met_cell{i};
    snr_v = NaN; mf_v = 0;
    if isfield(met,'SNR_dB'), snr_v = met.SNR_dB; end
    if isfield(met,'MF_Hz'),  mf_v  = met.MF_Hz;  end
    fprintf(' %-25s  %10.4f  %10.4f  %8.2f  %10.1f\n', ...
        label, rms_raw, rms_filt, snr_v, mf_v);
end

% Sol-Sağ EMG asimetri indexi
fprintf('\n── Sol-Sağ Asimetri İndeksi (|L-R|/(L+R)×100%%) ─────\n');
pairs = {1,2,'Trapezius'; 3,4,'Latissimus'; 5,6,'Erector Spinae'};
for p = 1:size(pairs,1)
    iL = pairs{p,1}; iR = pairs{p,2}; kas = pairs{p,3};
    if isempty(emg_filt_cell{iL}) || isempty(emg_filt_cell{iR}), continue; end
    rL = rms(emg_filt_cell{iL}); rR = rms(emg_filt_cell{iR});
    ai = abs(rL-rR)/(rL+rR)*100;
    flag = ''; if ai > EMG_ASYM, flag = '  ← EŞİK AŞILDI'; end
    fprintf(' %-18s : %.1f %%  (L=%.4f, R=%.4f)%s\n', kas, ai, rL, rR, flag);
end

fprintf('\n[Analiz tamamlandı]\n\n');

end % ── ana fonksiyon sonu ─────────────────────────────────────────────


% ======================================================================
%  YEREL YARDIMCI FONKSİYONLAR
% ======================================================================

% ── Tamamlayıcı Filtre ────────────────────────────────────────────────
function angle_cf = complementary_filter(acc, gyro, fs, alpha)
% COMPLEMENTARY_FILTER  ACC + GYRO tamamlayıcı filtresi
%   acc  : [N×3] ivme [g cinsinden] — sütun: X(ön-arka), Y(lateral), Z(yukarı)
%   gyro : [N×3] açısal hız [°/s]  — sütun: X(roll), Y(pitch), Z(yaw)
%   fs   : örnekleme frekansı [Hz]
%   alpha: filtre katsayısı (0.95–0.98 önerilir)
%
%   Döndürür: angle_cf [N×3] derece
%     sütun 1 = sagital fleksiyon (ACC pitch + GYRO.Y int.)
%     sütun 2 = frontal eğilme   (ACC roll  + GYRO.X int.)
%     sütun 3 = eksenel rotasyon (sadece GYRO.Z int. — mag. yok)

N  = size(acc, 1);
dt = 1 / fs;
angle_cf = zeros(N, 3);

% Yerçekimi normalizasyonu (g birimine göre)
acc_norm = sqrt(sum(acc.^2, 2));
acc_norm(acc_norm < 0.1) = 1;   % sıfıra bölmeyi önle
acc_g = acc ./ acc_norm;        % birim vektör

% Başlangıç açısı ACC'den
pitch_acc_init = atan2d(-acc_g(1,1), sqrt(acc_g(1,2).^2 + acc_g(1,3).^2));
roll_acc_init  = atan2d( acc_g(1,2), acc_g(1,3));
angle_cf(1,:) = [pitch_acc_init, roll_acc_init, 0];

for i = 2:N
    % ACC tabanlı açı (düşük frekans, kararlı)
    pitch_acc = atan2d(-acc_g(i,1), sqrt(acc_g(i,2)^2 + acc_g(i,3)^2));
    roll_acc  = atan2d( acc_g(i,2), acc_g(i,3));

    % GYRO entegrasyonu (yüksek frekans, kısa vadede hassas)
    pitch_g = angle_cf(i-1,1) + gyro(i,2) * dt;  % GYRO.Y → sagital pitch
    roll_g  = angle_cf(i-1,2) + gyro(i,1) * dt;  % GYRO.X → frontal roll
    yaw_g   = angle_cf(i-1,3) + gyro(i,3) * dt;  % GYRO.Z → eksenel yaw

    % Tamamlayıcı filtre birleşimi
    angle_cf(i,1) = alpha * pitch_g + (1-alpha) * pitch_acc;
    angle_cf(i,2) = alpha * roll_g  + (1-alpha) * roll_acc;
    angle_cf(i,3) = yaw_g;  % Sadece GYRO (manyetometre olmadan yaw düzeltilemez)
end
end

% ── Alt küme içinde eksen ara ─────────────────────────────────────────
function idx = findInSubset(ch_names, subset_idx, axis_kw)
% ch_names(subset_idx) içinde axis_kw içereni döndürür; bulamazsa boş.
hits = subset_idx(contains(ch_names(subset_idx), axis_kw, 'IgnoreCase', true));
if isempty(hits)
    idx = [];
else
    idx = hits(1);
end
end

% ── Veri matrisinden satır çek, NaN'ı sıfırla ────────────────────────
function row = getRow(data_mat, ch_idx, N_samp)
% ch_idx boşsa sıfır döndürür.
if isempty(ch_idx)
    row = zeros(N_samp, 1);
else
    row = double(data_mat(ch_idx(1), :))';
    row(isnan(row)) = 0;
end
end

% ── Index'i okunabilir stringe çevir ─────────────────────────────────
function s = idx2str(idx)
if isempty(idx), s = '–'; else, s = num2str(idx(1)); end
end
