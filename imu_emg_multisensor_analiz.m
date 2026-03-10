function imu_emg_multisensor_analiz(mat_file, egzersiz_adi)
% IMU_EMG_MULTISENSOR_ANALIZ  Skolyoz tedavi egzersizleri — tam preprocessing pipeline
%
% Pipeline:
%   EMG : detrend → baseline → BP(20-450Hz) → rectify → envelope(LP 10Hz) → normalize(max)
%   IMU : LP(10Hz) → integrate(∫GYRO dt) → baseline → segment → time-normalize → features
%
% Kullanım (Command Window'dan):
%   imu_emg_multisensor_analiz                        % dosya seçici
%   imu_emg_multisensor_analiz('kayit.mat')
%   imu_emg_multisensor_analiz('kayit.mat', 'SST Rep1')
%
% Bağımlılıklar (aynı klasörde):
%   advanced_filter.m   – butterworth / lowpass / notch
%   compute_metrics.m   – RMS, SNR, MF
%
% Delsys Trigno Avanti eksen sözleşmesi (sensör sırta düz):
%   GYRO.X → roll (lateral bend)   GYRO.Y → pitch (sagittal flex)
%   GYRO.Z → yaw (axial rotation)

% ======================================================================
%% 1. KONFİGÜRASYON
% ======================================================================

% ── Örnekleme frekansları (dosyadan otomatik okunur; bu yalnızca fallback) ─
IMU_FS = 148.15;    % [Hz]
EMG_FS = 1259.26;   % [Hz]

% ── IMU: alçak geçiren filtre + entegrasyon ────────────────────────────
IMU_LP_CUTOFF = 10;   % [Hz] yavaş iskelet hareketi için
IMU_LP_ORDER  = 4;
BASELINE_DUR  = 0.5;  % [s] ilk N saniye baseline sıfırlama için

% ── EMG: tam preprocessing ─────────────────────────────────────────────
EMG_BP_LOW    = 20;    % [Hz] bandpass alt
EMG_BP_HIGH   = 450;   % [Hz] bandpass üst
EMG_BP_ORDER  = 4;
EMG_NOTCH_F   = 50;    % [Hz] şebeke (TR=50 Hz)
EMG_NOTCH_Q   = 35;
EMG_ENV_CUTOFF = 10;   % [Hz] rectification sonrası envelope LP
EMG_ENV_ORDER  = 4;
EMG_BURST_THR  = 0.2;  % Normalize envelope → aktif sayılan eşik (0-1)

% ── Senkronizasyon (kanal başlangıç hizalama + iç boşluk doldurma) ────
SYNC_GAP_MAX_S   = 2.0;
SYNC_ZERO_MIN_S  = 0.05;
SYNC_ZERO_THRESH = 1e-9;

% ── Segmentasyon ───────────────────────────────────────────────────────
% Birincil sensör keywordu ve ekseni (angular velocity'de peak aranır)
SEG_SENSOR_KW    = 'T8T9';   % Hangi IMU sensörünün velocity'si kullanılsın
SEG_AXIS         = 2;        % 1=X(roll) 2=Y(pitch/sagittal) 3=Z(yaw)
SEG_METHOD       = 'peak';   % 'peak' | 'threshold'
SEG_PROM         = 15;       % [°/s] findpeaks MinPeakProminence
SEG_MIN_DUR      = 0.8;      % [s]   minimum rep süresi (MinPeakDistance)
SEG_THRESH_DEG_S = 15;       % [°/s] threshold yöntemi için eşik
SEG_MERGE_GAP_S  = 0.3;      % [s]   threshold yönteminde çok yakın sınırları birleştir

% ── Time normalization ─────────────────────────────────────────────────
N_NORM_PTS = 100;   % Her rep normalize edilecek nokta sayısı

% ── Klinik eşikler (PDF Tablo 10) ─────────────────────────────────────
THR_COMP   = 5;         % [°] tüm sensörler kompensasyon
THR_SST_Z  = [5 25];    % Seated Spinal Twist: T8T9 Z-rot hedef
THR_SSB_Y  = [5 30];    % Standing Side Bend: T8T9 Y-lat hedef
THR_WA_SC  = [10 20];   % Wall Angels: skapula X-rot hedef
EMG_ASYM   = 15;        % [%] sol-sağ EMG asimetri toleransı

% ── IMU sensör tanımları ───────────────────────────────────────────────
% Gerçek kanal isimlendirme (exerA dosyasından doğrulandı):
%   "IMU T1T2 (7): ACC.X 7"   "Sacrum (10): GYRO.Y 10"   "L scapula (11): ACC.Z 11"
IMU_DEF = {
    'T1T2',      'T1-T2  (Üst Torakal)',  [0.20 0.60 0.85];
    'T8T9',      'T8-T9  (Mid Torakal)',  [0.85 0.30 0.10];
    'L2L3',      'L2-L3  (Lumbar)',       [0.10 0.70 0.30];
    'Sacrum',    'Sakrum (Pelvis)',        [0.60 0.10 0.80];
    'L scapula', 'Sol Skapula',           [0.90 0.60 0.10];
    'R scapula', 'Sağ Skapula',           [0.30 0.80 0.80];
};

% ── EMG sensör tanımları ───────────────────────────────────────────────
% Gerçek isimlendirme: "L TRAPEZIUS (5): EMG 5"  "L LATISSIMUS DORSI (1): EMG 1"
EMG_DEF = {
    'L TRAPEZIUS',  'Sol Trapezius',      [0.20 0.60 0.85];
    'R TRAPEZIUS',  'Sağ Trapezius',      [0.85 0.30 0.10];
    'L LATISSIMUS', 'Sol Latissimus',     [0.10 0.70 0.30];
    'R LATISSIMUS', 'Sağ Latissimus',     [0.60 0.10 0.80];
    'L Erector',    'Sol Erector Spinae', [0.90 0.55 0.10];
    'R Erector',    'Sağ Erector Spinae', [0.30 0.80 0.80];
};

N_IMU = size(IMU_DEF, 1);
N_EMG = size(EMG_DEF, 1);

% ======================================================================
%% 2. VERİ YÜKLEME
% ======================================================================

if nargin < 1 || isempty(mat_file)
    [fn, fp] = uigetfile('*.mat', 'Delsys .mat dosyasını seçin');
    if isequal(fn, 0), disp('[iptal] Dosya seçilmedi.'); return; end
    mat_file = fullfile(fp, fn);
end
if nargin < 2 || isempty(egzersiz_adi), egzersiz_adi = ''; end

fprintf('\n======================================================\n');
fprintf(' IMU+EMG Çok Sensörlü Analiz\n');
fprintf(' Dosya   : %s\n', mat_file);
if ~isempty(egzersiz_adi), fprintf(' Egzersiz: %s\n', egzersiz_adi); end
fprintf('======================================================\n');

raw = load(mat_file);

if ~isfield(raw,'Channels') || ~isfield(raw,'Fs')
    error('Delsys formatı bulunamadı. Gerekli: Channels, Fs, Data');
end
if ~isfield(raw,'Data')
    if isfield(raw,'Time')
        fprintf('\n[HATA] Dosyada yalnızca Time (zaman ekseni) var, sinyal verisi YOK.\n');
        fprintf('  Çözüm: Delsys Lab → File → Export → MATLAB\n');
        fprintf('         Export Options: [✓] Data   [ ] Time\n\n');
    end
    error('Data değişkeni eksik.');
end

ch_names = string(raw.Channels(:));
fs_arr   = double(raw.Fs(:));
data_mat = double(raw.Data);
N_ch     = numel(ch_names);
N_samp   = size(data_mat, 2);

fprintf(' Kanal sayısı  : %d\n', N_ch);
fprintf(' Örnek sayısı  : %d\n', N_samp);
fprintf('\n Kanal listesi:\n');
for k = 1:N_ch
    r = data_mat(k,:);
    lv = find(~isnan(r), 1, 'last');
    dur = (lv / fs_arr(k)) * double(~isempty(lv));
    fprintf('   [%3d] %-50s  Fs=%7.2f  dur=%.1fs\n', k, ch_names(k), fs_arr(k), dur);
end
fprintf('\n');

% ======================================================================
%% 3. KANAL EŞLEŞME
% ======================================================================

imu_idx = struct();
imu_fs  = zeros(N_IMU, 1);

for i = 1:N_IMU
    kw    = IMU_DEF{i,1};
    label = IMU_DEF{i,2};
    base  = find(contains(ch_names, kw, 'IgnoreCase', true));
    if isempty(base)
        fprintf(' [UYARI] IMU bulunamadı: "%s" (%s)\n', kw, label);
        imu_idx(i).ok   = false;
        imu_idx(i).gyrX=[]; imu_idx(i).gyrY=[]; imu_idx(i).gyrZ=[];
        imu_idx(i).accX=[]; imu_idx(i).accY=[]; imu_idx(i).accZ=[];
        continue
    end
    imu_idx(i).ok   = true;
    imu_idx(i).accX = findInSubset(ch_names, base, 'ACC.X');
    imu_idx(i).accY = findInSubset(ch_names, base, 'ACC.Y');
    imu_idx(i).accZ = findInSubset(ch_names, base, 'ACC.Z');
    imu_idx(i).gyrX = findInSubset(ch_names, base, 'GYRO.X');
    imu_idx(i).gyrY = findInSubset(ch_names, base, 'GYRO.Y');
    imu_idx(i).gyrZ = findInSubset(ch_names, base, 'GYRO.Z');
    imu_fs(i) = get_ch_fs(fs_arr, imu_idx(i).gyrX, IMU_FS);
    fprintf(' IMU %d %-22s → GYRO:[%s %s %s]  Fs=%.2f\n', ...
        i, label, idx2str(imu_idx(i).gyrX), idx2str(imu_idx(i).gyrY), ...
        idx2str(imu_idx(i).gyrZ), imu_fs(i));
end

emg_idx = zeros(N_EMG,1);
emg_fs  = zeros(N_EMG,1);

for i = 1:N_EMG
    kw    = EMG_DEF{i,1};
    label = EMG_DEF{i,2};
    hits  = find(contains(ch_names, kw, 'IgnoreCase', true) & ...
                 contains(ch_names, 'EMG', 'IgnoreCase', true));
    if isempty(hits)
        hits = find(contains(ch_names, kw, 'IgnoreCase', true));
    end
    if isempty(hits)
        fprintf(' [UYARI] EMG bulunamadı: "%s" (%s)\n', kw, label);
    else
        emg_idx(i) = hits(1);
        emg_fs(i)  = fs_arr(hits(1));
        fprintf(' EMG %d %-22s → kanal %d  Fs=%.2f\n', i, label, hits(1), emg_fs(i));
    end
end
fprintf('\n');

% ======================================================================
%% 3.5. SENKRONIZASYON
% ======================================================================

fprintf(' [SYNC] Kanal hizalama + boşluk doldurma...\n');

data_sync   = data_mat;
ch_tstart_s = zeros(N_ch, 1);

for k = 1:N_ch
    fs_k = fs_arr(k); if fs_k <= 0, fs_k = 1; end
    row_k = data_mat(k,:);
    valid_mask = ~isnan(row_k) & (abs(row_k) > SYNC_ZERO_THRESH);
    fv = find(valid_mask, 1, 'first');
    lv = find(valid_mask, 1, 'last');
    if isempty(fv), continue; end
    ch_tstart_s(k) = (fv-1) / fs_k;
    seg = double(row_k(fv:lv));
    data_sync(k, fv:lv) = fill_gaps_1d(seg, fs_k, SYNC_GAP_MAX_S, ...
                                        SYNC_ZERO_THRESH, SYNC_ZERO_MIN_S);
end

active_chs = [];
for i = 1:N_IMU
    if ~imu_idx(i).ok, continue; end
    for fn = {'gyrX','gyrY','gyrZ','accX','accY','accZ'}
        ci = imu_idx(i).(fn{1});
        if ~isempty(ci), active_chs(end+1) = ci; end %#ok<AGROW>
    end
end
for i = 1:N_EMG
    if emg_idx(i) > 0, active_chs(end+1) = emg_idx(i); end %#ok<AGROW>
end
active_chs = unique(active_chs);

if isempty(active_chs)
    T_GLOBAL_START = 0;
else
    T_GLOBAL_START = max(ch_tstart_s(active_chs));
end
fprintf(' [SYNC] t=0: %.3f s  |  kanal aralığı: %.3f–%.3f s\n', ...
    T_GLOBAL_START, min(ch_tstart_s(active_chs)), max(ch_tstart_s(active_chs)));
fprintf('\n');

% ======================================================================
%% 4. IMU: ALÇAK GEÇİREN FİLTRE + ENTEGRASYON
% ======================================================================
% Pipeline: GYRO ham → LP(10Hz) → ∫dt → baseline subtract
% Açıklama:
%   - GYRO [°/s] × dt [s] = açı değişimi [°]
%   - cumsum(gyro_lp) * dt → kümülatif açı
%   - LP filtre: yavaş hareketlerde >10 Hz yüksek frekans gürültüsü

fprintf(' [IMU] LP filtre + entegrasyon...\n');

imu_angle_cell  = cell(N_IMU, 1);  % [N×3] açı (°)
imu_gyrolp_cell = cell(N_IMU, 1);  % [N×3] LP-filtreli angular velocity (°/s)
imu_time_cell   = cell(N_IMU, 1);

params_lp_imu = struct('cutoff', IMU_LP_CUTOFF, 'order', IMU_LP_ORDER);

for i = 1:N_IMU
    label = IMU_DEF{i,2};
    if ~imu_idx(i).ok
        fprintf('   %-22s → ATLANDI (kanal yok)\n', label);
        continue
    end
    fs_i = imu_fs(i); if fs_i <= 0, fs_i = IMU_FS; end
    dt   = 1/fs_i;

    i_start = max(1, round(T_GLOBAL_START * fs_i) + 1);
    n_avail = N_samp - i_start + 1;
    if n_avail < 10
        fprintf('   %-22s → ATLANDI (senkron sonrası yetersiz örnek)\n', label);
        continue
    end

    % GYRO kanallarını çek (boşluk doldurulmuş veriden, global t=0'dan)
    gyrX = getRowSync(data_sync, imu_idx(i).gyrX, n_avail, i_start);
    gyrY = getRowSync(data_sync, imu_idx(i).gyrY, n_avail, i_start);
    gyrZ = getRowSync(data_sync, imu_idx(i).gyrZ, n_avail, i_start);

    % Son geçerli örneği bul (trailing NaN kırp)
    all_gyro = [gyrX, gyrY, gyrZ];
    valid = find(~any(isnan(all_gyro), 2), 1, 'last');
    if isempty(valid) || valid < 10
        fprintf('   %-22s → ATLANDI (geçerli GYRO < 10 örnek)\n', label);
        continue
    end
    gyrX = gyrX(1:valid); gyrY = gyrY(1:valid); gyrZ = gyrZ(1:valid);

    % ── Adım 1: Alçak geçiren filtre (10 Hz) ─────────────────────────
    try
        gX_lp = advanced_filter(gyrX, fs_i, 'lowpass', params_lp_imu);
        gY_lp = advanced_filter(gyrY, fs_i, 'lowpass', params_lp_imu);
        gZ_lp = advanced_filter(gyrZ, fs_i, 'lowpass', params_lp_imu);
    catch err
        fprintf('   [UYARI] IMU LP filtre hatası (%s): %s\n', label, err.message);
        gX_lp = gyrX; gY_lp = gyrY; gZ_lp = gyrZ;
    end
    gyro_lp = [gX_lp, gY_lp, gZ_lp];

    % ── Adım 2: Entegrasyon (∫GYRO_lp dt → açı) ──────────────────────
    angle = cumsum(gyro_lp, 1) * dt;   % [valid×3] derece

    % ── Adım 3: Baseline sıfırlama ────────────────────────────────────
    n_base = max(1, round(BASELINE_DUR * fs_i));
    angle  = angle - mean(angle(1:n_base, :), 1);

    imu_angle_cell{i}  = angle;      % [valid×3]
    imu_gyrolp_cell{i} = gyro_lp;   % segmentasyon için sakla
    imu_time_cell{i}   = (0:valid-1)' / fs_i;

    mx = max(abs(angle), [], 1);
    fprintf('   %-22s → %5d örnek | %5.1fs | MaksX=%5.1f° Y=%5.1f° Z=%5.1f°\n', ...
        label, valid, valid/fs_i, mx(1), mx(2), mx(3));
end
fprintf('\n');

% ======================================================================
%% 5. EMG: TAM PREPROCESSİNG PİPELİNE
% ======================================================================
% detrend → baseline → BP(20-450Hz)+Notch → rectify → envelope(LP 10Hz) → /max

fprintf(' [EMG] Tam preprocessing...\n');

emg_stages_cell = cell(N_EMG, 1);  % Her kanalın tüm aşamaları
emg_time_cell   = cell(N_EMG, 1);
emg_met_cell    = cell(N_EMG, 1);

params_bp   = struct('low', EMG_BP_LOW, 'high', EMG_BP_HIGH, 'order', EMG_BP_ORDER);
params_n    = struct('f_notch', EMG_NOTCH_F, 'Q', EMG_NOTCH_Q);
params_lp_e = struct('cutoff', EMG_ENV_CUTOFF, 'order', EMG_ENV_ORDER);

for i = 1:N_EMG
    label = EMG_DEF{i,2};
    if emg_idx(i) == 0
        fprintf('   %-22s → ATLANDI\n', label);
        continue
    end
    fs_e = emg_fs(i); if fs_e <= 0, fs_e = EMG_FS; end

    i_start_e = max(1, round(T_GLOBAL_START * fs_e) + 1);
    n_avail_e = N_samp - i_start_e + 1;
    if n_avail_e < 20
        fprintf('   %-22s → ATLANDI (senkron sonrası yetersiz)\n', label);
        continue
    end

    raw_full = double(data_sync(emg_idx(i), i_start_e:min(end, i_start_e+n_avail_e-1)))';
    lv = find(~isnan(raw_full), 1, 'last');
    if isempty(lv) || lv < 20
        fprintf('   %-22s → ATLANDI (geçerli veri yok)\n', label);
        continue
    end
    raw_v = raw_full(1:lv);
    raw_v(isnan(raw_v)) = 0;

    % ── Adım 1: Detrend ──────────────────────────────────────────────
    emg_dt = detrend(raw_v);

    % ── Adım 2: Baseline correction ──────────────────────────────────
    n_base_e = max(1, round(BASELINE_DUR * fs_e));
    emg_bl   = emg_dt - mean(emg_dt(1:n_base_e));

    % ── Adım 3: Bandpass + Notch ─────────────────────────────────────
    try
        emg_bp = advanced_filter(emg_bl, fs_e, 'butterworth', params_bp);
        emg_bp = advanced_filter(emg_bp, fs_e, 'notch',       params_n);
    catch err
        fprintf('   [UYARI] EMG BP/Notch hatası (%s): %s\n', label, err.message);
        emg_bp = emg_bl;
    end

    % ── Adım 4: Tam-dalga rectification ─────────────────────────────
    emg_rect = abs(emg_bp);

    % ── Adım 5: Envelope (LP 10 Hz) ──────────────────────────────────
    try
        emg_env = advanced_filter(emg_rect, fs_e, 'lowpass', params_lp_e);
    catch err
        fprintf('   [UYARI] EMG envelope LP hatası (%s): %s\n', label, err.message);
        emg_env = emg_rect;
    end

    % ── Adım 6: Amplitude normalization (max = 1) ─────────────────────
    max_val = max(emg_env);
    if max_val > 0
        emg_norm = emg_env / max_val;
    else
        emg_norm = emg_env;
    end

    % Metrikler (BP sinyali üzerinden — rectification öncesi)
    try
        met = compute_metrics(emg_bp, fs_e, raw_v);
    catch
        met = struct('RMS', rms(emg_bp), 'SNR_dB', NaN, 'MF_Hz', 0);
    end

    emg_stages_cell{i} = struct( ...
        'raw',  raw_v, ...
        'bp',   emg_bp, ...
        'rect', emg_rect, ...
        'env',  emg_env, ...
        'norm', emg_norm, ...
        'fs',   fs_e);
    emg_time_cell{i} = (0:lv-1)' / fs_e;
    emg_met_cell{i}  = met;

    fprintf('   %-22s → %6d örnek | %5.1fs | RMS_bp=%.4f | MaxEnv=%.4f\n', ...
        label, lv, lv/fs_e, met.RMS, max_val);
end
fprintf('\n');

% ======================================================================
%% 5.5. SEGMENTASYON
% ======================================================================
% Angular velocity (LP filtreli GYRO) üzerinden rep tespiti
% Velocity sinyali açıya göre daha belirgin peak verir

fprintf(' [SEG] Rep tespiti (%s yöntemi, sensör: %s eksen=%d)...\n', ...
    SEG_METHOD, SEG_SENSOR_KW, SEG_AXIS);

rep_start_imu = [];
rep_end_imu   = [];
seg_fs_i      = IMU_FS;
seg_sensor_found = false;

% Segmentasyon sensörünü bul
for i = 1:N_IMU
    if contains(IMU_DEF{i,1}, SEG_SENSOR_KW, 'IgnoreCase', true) && ~isempty(imu_gyrolp_cell{i})
        vel = imu_gyrolp_cell{i}(:, SEG_AXIS);
        seg_fs_i = imu_fs(i); if seg_fs_i <= 0, seg_fs_i = IMU_FS; end
        seg_sensor_found = true;

        if strcmp(SEG_METHOD, 'peak')
            % İleri ve geri hareket pikleri
            min_dist_samp = round(SEG_MIN_DUR * seg_fs_i);
            try
                [~, pk_p] = findpeaks( vel, 'MinPeakProminence', SEG_PROM, ...
                                             'MinPeakDistance',   min_dist_samp);
                [~, pk_n] = findpeaks(-vel, 'MinPeakProminence', SEG_PROM, ...
                                             'MinPeakDistance',   min_dist_samp);
            catch
                pk_p = []; pk_n = [];
            end
            all_peaks = sort([pk_p; pk_n]);

            % Ardışık peak çiftleri → rep başı-sonu
            if numel(all_peaks) >= 2
                rep_start_imu = all_peaks(1:end-1);
                rep_end_imu   = all_peaks(2:end);
                % Minimum süre filtresi
                dur_samp = rep_end_imu - rep_start_imu;
                ok = dur_samp >= round(SEG_MIN_DUR * seg_fs_i);
                rep_start_imu = rep_start_imu(ok);
                rep_end_imu   = rep_end_imu(ok);
            end

        else   % 'threshold'
            crossing = abs(vel) > SEG_THRESH_DEG_S;
            rs = find(diff([0; crossing]) ==  1);
            re = find(diff([crossing; 0]) == -1);
            % Çok yakın segmentleri birleştir
            merge_samp = round(SEG_MERGE_GAP_S * seg_fs_i);
            if ~isempty(rs)
                merged_s = rs(1); merged_e = re(1);
                for k = 2:numel(rs)
                    if rs(k) - merged_e(end) < merge_samp
                        merged_e(end) = re(k);
                    else
                        merged_s(end+1) = rs(k); %#ok<AGROW>
                        merged_e(end+1) = re(k); %#ok<AGROW>
                    end
                end
                rep_start_imu = merged_s(:);
                rep_end_imu   = merged_e(:);
            end
        end
        break
    end
end

N_reps = numel(rep_start_imu);
if ~seg_sensor_found
    fprintf('   [UYARI] Segmentasyon sensörü "%s" bulunamadı — segmentasyon atlandı.\n', SEG_SENSOR_KW);
elseif N_reps == 0
    fprintf('   [UYARI] Hiç rep tespit edilemedi. SEG_PROM/SEG_THRESH değerlerini düşürün.\n');
else
    dur_mean = mean((rep_end_imu - rep_start_imu) / seg_fs_i);
    fprintf('   Tespit edilen rep sayısı: %d  |  Ortalama süre: %.2f s\n', N_reps, dur_mean);
    for r = 1:N_reps
        fprintf('     Rep %2d: %.2f s – %.2f s  (%.2f s)\n', r, ...
            rep_start_imu(r)/seg_fs_i, rep_end_imu(r)/seg_fs_i, ...
            (rep_end_imu(r)-rep_start_imu(r))/seg_fs_i);
    end
end
fprintf('\n');

% ======================================================================
%% 5.6. TIME NORMALIZATION
% ======================================================================
% Her rep: IMU açı + EMG envelope → 100 nokta cubic (pchip) interpolasyon

t_norm_axis = linspace(0, 1, N_NORM_PTS)';  % normalize zaman ekseni

% Hücre dizileri: {sensor_i}[N_reps × N_NORM_PTS × 3] ve {emg_i}[N_reps × N_NORM_PTS]
norm_imu = cell(N_IMU, 1);
norm_emg = cell(N_EMG, 1);

if N_reps > 0
    fprintf(' [NORM] %d rep, %d nokta cubic interpolasyon...\n', N_reps, N_NORM_PTS);

    for i = 1:N_IMU
        if isempty(imu_angle_cell{i}), continue; end
        fs_i = imu_fs(i); if fs_i <= 0, fs_i = IMU_FS; end
        ang  = imu_angle_cell{i};  % [M×3]
        norm_imu{i} = zeros(N_reps, N_NORM_PTS, 3);

        for r = 1:N_reps
            s = rep_start_imu(r); e = rep_end_imu(r);
            if s < 1 || e > size(ang,1) || e <= s, continue; end
            seg_ang = ang(s:e, :);        % [seg_len×3]
            n_seg   = size(seg_ang, 1);
            t_seg   = linspace(0, 1, n_seg)';
            for ax = 1:3
                norm_imu{i}(r,:,ax) = interp1(t_seg, seg_ang(:,ax), t_norm_axis, 'pchip');
            end
        end
    end

    for i = 1:N_EMG
        if isempty(emg_stages_cell{i}), continue; end
        fs_e     = emg_stages_cell{i}.fs;
        emg_nrm  = emg_stages_cell{i}.norm;  % normalize envelope [0-1]
        norm_emg{i} = zeros(N_reps, N_NORM_PTS);

        for r = 1:N_reps
            % IMU sample zamanını gerçek süreye çevir, EMG indeksine eşleştir
            t_rep_s   = [rep_start_imu(r)-1, rep_end_imu(r)] / seg_fs_i;
            es = max(1, round(t_rep_s(1) * fs_e) + 1);
            ee = min(numel(emg_nrm), round(t_rep_s(2) * fs_e));
            if ee <= es + 2, continue; end
            seg_emg = emg_nrm(es:ee);
            t_seg_e = linspace(0, 1, numel(seg_emg))';
            norm_emg{i}(r,:) = interp1(t_seg_e, seg_emg, t_norm_axis, 'pchip');
        end
    end
    fprintf('   Time normalization tamamlandı.\n\n');
end

% ======================================================================
%% 5.7. FEATURE EXTRACTION
% ======================================================================

feats = struct([]);  % rep bazlı özellik tablosu

if N_reps > 0
    fprintf(' [FEAT] Rep bazlı özellik çıkarımı...\n');

    for r = 1:N_reps
        feats(r).rep      = r;
        feats(r).dur_s    = (rep_end_imu(r)-rep_start_imu(r)) / seg_fs_i;

        % IMU özellikleri (her sensör, her eksen)
        for i = 1:N_IMU
            label = strrep(IMU_DEF{i,2}, ' ', '_');
            label = regexprep(label, '[^a-zA-Z0-9_]', '');
            if isempty(imu_angle_cell{i}), continue; end
            s = rep_start_imu(r); e = rep_end_imu(r);
            if e > size(imu_angle_cell{i},1), continue; end
            ang_seg = imu_angle_cell{i}(s:e, :);
            vel_seg = imu_gyrolp_cell{i}(min(s,size(imu_gyrolp_cell{i},1)):min(e,size(imu_gyrolp_cell{i},1)), :);
            feats(r).(['ROM_X_' label]) = max(ang_seg(:,1)) - min(ang_seg(:,1));
            feats(r).(['ROM_Y_' label]) = max(ang_seg(:,2)) - min(ang_seg(:,2));
            feats(r).(['ROM_Z_' label]) = max(ang_seg(:,3)) - min(ang_seg(:,3));
            feats(r).(['PkVel_' label]) = max(abs(vel_seg(:)));
        end

        % EMG özellikleri
        for i = 1:N_EMG
            label = strrep(EMG_DEF{i,2}, ' ', '_');
            label = regexprep(label, '[^a-zA-Z0-9_]', '');
            if isempty(emg_stages_cell{i}), continue; end
            fs_e   = emg_stages_cell{i}.fs;
            en     = emg_stages_cell{i}.norm;
            t_s    = (rep_start_imu(r)-1) / seg_fs_i;
            t_e    = rep_end_imu(r) / seg_fs_i;
            es     = max(1, round(t_s*fs_e)+1);
            ee     = min(numel(en), round(t_e*fs_e));
            if ee <= es, continue; end
            seg_en = en(es:ee);
            feats(r).(['EMG_Peak_' label]) = max(seg_en);
            feats(r).(['EMG_Mean_' label]) = mean(seg_en);
            feats(r).(['EMG_Burst_' label]) = sum(seg_en > EMG_BURST_THR)/fs_e;
        end
    end

    fprintf('   %d rep için özellikler hesaplandı.\n\n', N_reps);
end

% ======================================================================
%% 6. GRAFİKLER
% ======================================================================

ax_col  = [0.12 0.12 0.16];
txt_col = [0.88 0.88 0.88];
grd_col = [0.25 0.25 0.30];
ax_clr  = {[0.95 0.25 0.25],[0.25 0.55 0.95],[0.25 0.85 0.45]};
ax_lbl  = {'X(roll/lat)','Y(pitch/sag)','Z(yaw/rot)'};

[~, fn_short, ext] = fileparts(mat_file);
title_base = sprintf('IMU+EMG  —  %s%s', fn_short, ext);
if ~isempty(egzersiz_adi), title_base = [title_base, '  |  ', egzersiz_adi]; end

%% ── Figure 1: Tam zaman serisi + segmentasyon işaretleri ─────────────

fig1 = figure('Name', 'Fig1 – Zaman Serisi', 'Position', [20 30 1700 940], ...
    'Color', [0.10 0.10 0.13]);
tl1 = tiledlayout(fig1, 4, 3, 'TileSpacing','compact','Padding','compact');
title(tl1, title_base, 'FontSize',12,'FontWeight','bold','Color',txt_col);

% IMU subplotları (tile 1-6)
for i = 1:N_IMU
    ax = nexttile(tl1);
    set(ax,'Color',ax_col,'XColor',txt_col,'YColor',txt_col, ...
        'GridColor',grd_col,'FontSize',8,'Box','on');
    grid(ax,'on'); hold(ax,'on');
    col_s = IMU_DEF{i,3};
    lbl   = IMU_DEF{i,2};

    if isempty(imu_angle_cell{i})
        text(ax,0.5,0.5,sprintf('Kanal yok\n(%s)',IMU_DEF{i,1}), ...
            'HorizontalAlignment','center','Color',[0.5 0.5 0.5],'FontSize',9);
        title(ax,lbl,'Color',col_s,'FontSize',9,'FontWeight','bold'); continue
    end

    t_i   = imu_time_cell{i};
    ang   = imu_angle_cell{i};

    % ±5° eşik
    yline(ax, THR_COMP,'--','Color',[0.95 0.45 0.10],'LineWidth',1.1,'HandleVisibility','off');
    yline(ax,-THR_COMP,'--','Color',[0.95 0.45 0.10],'LineWidth',1.1,'HandleVisibility','off');
    yline(ax, 0, '-','Color',[0.50 0.50 0.55],'LineWidth',0.7,'HandleVisibility','off');

    for ax_k = 1:3
        plot(ax, t_i, ang(:,ax_k), 'Color',ax_clr{ax_k}, 'LineWidth',0.9);
    end

    % Segmentasyon dikey çizgileri
    if N_reps > 0 && imu_fs(i) > 0
        for r = 1:N_reps
            ts = rep_start_imu(r)/imu_fs(i);
            te = rep_end_imu(r)/imu_fs(i);
            xline(ax,ts,'--','Color',[0.7 0.7 0.0 0.7],'LineWidth',0.9,'HandleVisibility','off');
            xline(ax,te,':','Color',[0.7 0.7 0.0 0.5],'LineWidth',0.7,'HandleVisibility','off');
        end
    end

    legend(ax, ax_lbl, 'TextColor',txt_col,'Color',ax_col,'FontSize',7,'Location','northeast','Box','off');
    xlabel(ax,'Zaman (s)','Color',txt_col,'FontSize',8);
    ylabel(ax,'Açı (°)','Color',txt_col,'FontSize',8);
    title(ax, lbl,'Color',col_s,'FontSize',9,'FontWeight','bold');
end

% EMG subplotları (tile 7-12)
for i = 1:N_EMG
    ax = nexttile(tl1);
    set(ax,'Color',ax_col,'XColor',txt_col,'YColor',txt_col, ...
        'GridColor',grd_col,'FontSize',8,'Box','on');
    grid(ax,'on'); hold(ax,'on');
    col_s = EMG_DEF{i,3};
    lbl   = EMG_DEF{i,2};

    if isempty(emg_stages_cell{i})
        text(ax,0.5,0.5,sprintf('Kanal yok\n(%s)',EMG_DEF{i,1}), ...
            'HorizontalAlignment','center','Color',[0.5 0.5 0.5],'FontSize',9);
        title(ax,lbl,'Color',col_s,'FontSize',9,'FontWeight','bold'); continue
    end

    t_e  = emg_time_cell{i};
    stgs = emg_stages_cell{i};
    met  = emg_met_cell{i};

    % Ham (gri, arka) + BP (açık renk) + Envelope (renkli, kalın) + Norm (alt panel)
    plot(ax, t_e, stgs.raw,  'Color',[0.45 0.45 0.45 0.30],'LineWidth',0.4);
    plot(ax, t_e, stgs.bp,   'Color',[col_s 0.50],          'LineWidth',0.5);
    plot(ax, t_e, stgs.env,  'Color',col_s,                 'LineWidth',1.2);

    % Normalize envelope (sağ y-eksenine gerek yok, scale bilgisi yeter — overlay)
    yyaxis(ax, 'right');
    set(ax,'YColor',[0.65 0.65 0.65]);
    plot(ax, t_e, stgs.norm, 'Color',[0.90 0.85 0.20 0.80], 'LineWidth',0.8);
    ylabel(ax, 'Norm (0-1)', 'Color',[0.65 0.65 0.65],'FontSize',7);
    yyaxis(ax,'left');

    % Metrik kutusu
    snr_s = ''; mf_s = '';
    if isfield(met,'SNR_dB') && isfinite(met.SNR_dB), snr_s = sprintf(' SNR=%.1fdB',met.SNR_dB); end
    if isfield(met,'MF_Hz') && met.MF_Hz > 0, mf_s = sprintf(' MF=%.0fHz',met.MF_Hz); end
    text(ax, t_e(end)*0.98, max(stgs.env)*0.88, ...
        sprintf('RMS=%.4f%s%s', met.RMS, snr_s, mf_s), ...
        'HorizontalAlignment','right','FontSize',7,'Color',col_s, ...
        'BackgroundColor',[ax_col 0.7]);

    legend(ax,{'Ham','BP','Envelope','Norm'}, ...
        'TextColor',txt_col,'Color',ax_col,'FontSize',6,'Location','northwest','Box','off');
    xlabel(ax,'Zaman (s)','Color',txt_col,'FontSize',8);
    ylabel(ax,'Amplitüd (mV)','Color',txt_col,'FontSize',8);
    title(ax,lbl,'Color',col_s,'FontSize',9,'FontWeight','bold');
end

annotation(fig1,'textbox',[0.01 0.002 0.99 0.022], ...
    'String', sprintf(['LP IMU: %.0fHz | ∫dt→Açı° | EMG: detrend→BP(%d-%dHz)→rect→env(LP%.0fHz)→/max' ...
                       ' | ±%.0f° eşik | Sarı dikey: rep sınırları'], ...
    IMU_LP_CUTOFF, EMG_BP_LOW, EMG_BP_HIGH, EMG_ENV_CUTOFF, THR_COMP), ...
    'FitBoxToText','off','EdgeColor','none','Color',[0.55 0.55 0.55],'FontSize',7,'BackgroundColor','none');

%% ── Figure 2: Time-normalized rep overlay ────────────────────────────

if N_reps > 0
    fig2 = figure('Name','Fig2 – Time-Normalized Reps','Position',[40 40 1700 900], ...
        'Color',[0.10 0.10 0.13]);
    tl2 = tiledlayout(fig2, 3, 4, 'TileSpacing','compact','Padding','compact');
    title(tl2, sprintf('%s  |  Time-Normalized Reps (n=%d)', title_base, N_reps), ...
        'FontSize',11,'FontWeight','bold','Color',txt_col);

    rep_colors = lines(max(N_reps,1));

    % IMU: tiles 1-6 (sütun 1-2, 3 satır)
    imu_tile_order = [1 2; 5 6; 9 10];   % 3×2 blok: sol 6 tile
    imu_plot_idx = [1 5 9 2 6 10];        % tiles 1,5,9,2,6,10

    for i = 1:N_IMU
        ax = nexttile(tl2, imu_plot_idx(i));
        set(ax,'Color',ax_col,'XColor',txt_col,'YColor',txt_col, ...
            'GridColor',grd_col,'FontSize',8,'Box','on');
        grid(ax,'on'); hold(ax,'on');
        col_s = IMU_DEF{i,3};

        if isempty(norm_imu{i})
            title(ax, [IMU_DEF{i,2} ' (veri yok)'],'Color',col_s,'FontSize',8,'FontWeight','bold'); continue
        end

        for ax_k = 1:3
            data_reps = squeeze(norm_imu{i}(:,:,ax_k));  % [N_reps × N_NORM_PTS]
            for r = 1:N_reps
                plot(ax, t_norm_axis, data_reps(r,:), ...
                    'Color',[ax_clr{ax_k} 0.35], 'LineWidth',0.7);
            end
            if N_reps > 1
                plot(ax, t_norm_axis, mean(data_reps,1), ...
                    'Color',ax_clr{ax_k},'LineWidth',2.5);
                mu  = mean(data_reps,1);
                sig = std(data_reps, 0, 1);
                fill(ax,[t_norm_axis; flipud(t_norm_axis)], ...
                    [mu'-sig'; flipud(mu'+sig')], ax_clr{ax_k}, ...
                    'FaceAlpha',0.12,'EdgeColor','none','HandleVisibility','off');
            end
        end

        yline(ax, THR_COMP,'--','Color',[0.95 0.45 0.10],'LineWidth',0.9,'HandleVisibility','off');
        yline(ax,-THR_COMP,'--','Color',[0.95 0.45 0.10],'LineWidth',0.9,'HandleVisibility','off');
        xlabel(ax,'Normalize süre','Color',txt_col,'FontSize',7);
        ylabel(ax,'Açı (°)','Color',txt_col,'FontSize',7);
        title(ax, IMU_DEF{i,2},'Color',col_s,'FontSize',8,'FontWeight','bold');
    end

    % EMG: tiles 3-4, 7-8, 11-12 (sağ 6 tile)
    emg_tile_order = [3 4; 7 8; 11 12];
    emg_plot_idx   = [3 4 7 8 11 12];

    for i = 1:N_EMG
        ax = nexttile(tl2, emg_plot_idx(i));
        set(ax,'Color',ax_col,'XColor',txt_col,'YColor',txt_col, ...
            'GridColor',grd_col,'FontSize',8,'Box','on');
        grid(ax,'on'); hold(ax,'on');
        col_s = EMG_DEF{i,3};

        if isempty(norm_emg{i})
            title(ax,[EMG_DEF{i,2} ' (veri yok)'],'Color',col_s,'FontSize',8,'FontWeight','bold'); continue
        end

        for r = 1:N_reps
            plot(ax, t_norm_axis, norm_emg{i}(r,:), ...
                'Color',[col_s 0.35], 'LineWidth',0.7);
        end
        if N_reps > 1
            mu  = mean(norm_emg{i}, 1);
            sg  = std(norm_emg{i},  0, 1);
            plot(ax, t_norm_axis, mu, 'Color',col_s, 'LineWidth',2.5);
            fill(ax,[t_norm_axis; flipud(t_norm_axis)], ...
                [mu'-sg'; flipud(mu'+sg')], col_s, ...
                'FaceAlpha',0.15,'EdgeColor','none');
        end
        yline(ax, EMG_BURST_THR,'--','Color',[0.8 0.8 0.2 0.7],'LineWidth',0.9,'HandleVisibility','off');
        xlabel(ax,'Normalize süre','Color',txt_col,'FontSize',7);
        ylabel(ax,'Norm ENV (0-1)','Color',txt_col,'FontSize',7);
        title(ax, EMG_DEF{i,2},'Color',col_s,'FontSize',8,'FontWeight','bold');
    end
end

% ======================================================================
%% 7. ÖZET TABLO (konsol)
% ======================================================================

fprintf('\n======================================================\n');
fprintf(' SENKRONIZASYON  —  Global t=0: %.3f s\n', T_GLOBAL_START);
fprintf('======================================================\n');

fprintf('\n======================================================\n');
fprintf(' IMU — MAKSİMUM AÇILAR\n');
fprintf('======================================================\n');
fprintf(' %-22s  %8s  %8s  %8s  %10s\n', 'Sensör','MaksX(°)','MaksY(°)','MaksZ(°)','Eşik>5°');
fprintf(' %s\n', repmat('-',1,65));
for i = 1:N_IMU
    lbl = IMU_DEF{i,2};
    if isempty(imu_angle_cell{i})
        fprintf(' %-22s  %8s  %8s  %8s  %10s\n',lbl,'—','—','—','—'); continue
    end
    ang = imu_angle_cell{i};
    mx  = max(abs(ang),[],1);
    n_o = sum(max(abs(ang),[],2) > THR_COMP);
    t_o = n_o / imu_fs(i);
    tos = 'YOK'; if n_o > 0, tos = sprintf('%.1fs',t_o); end
    fprintf(' %-22s  %8.2f  %8.2f  %8.2f  %10s\n',lbl,mx(1),mx(2),mx(3),tos);
end

fprintf('\n======================================================\n');
fprintf(' EMG — METRİKLER\n');
fprintf('======================================================\n');
fprintf(' %-22s  %10s  %10s  %8s  %8s\n','Kas','RMS_ham','RMS_bp','SNR(dB)','MF(Hz)');
fprintf(' %s\n', repmat('-',1,65));
for i = 1:N_EMG
    lbl = EMG_DEF{i,2};
    if isempty(emg_stages_cell{i})
        fprintf(' %-22s  %10s  %10s  %8s  %8s\n',lbl,'—','—','—','—'); continue
    end
    met = emg_met_cell{i};
    rr  = rms(emg_stages_cell{i}.raw);
    rb  = met.RMS;
    snr = NaN; mf = 0;
    if isfield(met,'SNR_dB'), snr = met.SNR_dB; end
    if isfield(met,'MF_Hz'),  mf  = met.MF_Hz;  end
    fprintf(' %-22s  %10.4f  %10.4f  %8.2f  %8.1f\n',lbl,rr,rb,snr,mf);
end

fprintf('\n── Sol-Sağ EMG Asimetri İndeksi ─────────────────────\n');
pairs = {1,2,'Trapezius'; 3,4,'Latissimus'; 5,6,'Erector'};
for p = 1:3
    iL=pairs{p,1}; iR=pairs{p,2}; kas=pairs{p,3};
    if isempty(emg_stages_cell{iL}) || isempty(emg_stages_cell{iR}), continue; end
    rL = rms(emg_stages_cell{iL}.bp);
    rR = rms(emg_stages_cell{iR}.bp);
    ai = abs(rL-rR)/(rL+rR)*100;
    flg = ''; if ai > EMG_ASYM, flg = '  ← EŞİK AŞILDI'; end
    fprintf(' %-14s : %5.1f%%  (L=%.4f R=%.4f)%s\n', kas, ai, rL, rR, flg);
end

if N_reps > 0
    fprintf('\n======================================================\n');
    fprintf(' REP BAZLI TABLO\n');
    fprintf('======================================================\n');
    fprintf(' %-4s  %-6s', 'Rep','Süre(s)');
    for i = 1:N_IMU
        if isempty(imu_angle_cell{i}), continue; end
        lbl = IMU_DEF{i,2}(1:min(8,end));
        fprintf('  %7s_Y  %7s_Z', lbl, lbl);
    end
    fprintf('\n %s\n', repmat('-',1,80));
    for r = 1:N_reps
        fprintf(' %-4d  %-6.2f', r, feats(r).dur_s);
        for i = 1:N_IMU
            lbl = strrep(IMU_DEF{i,2},' ','_');
            lbl = regexprep(lbl,'[^a-zA-Z0-9_]','');
            fy = NaN; fz = NaN;
            if isfield(feats,['ROM_Y_' lbl]), fy = feats(r).(['ROM_Y_' lbl]); end
            if isfield(feats,['ROM_Z_' lbl]), fz = feats(r).(['ROM_Z_' lbl]); end
            if isnan(fy), fprintf('  %10s', '—'); else, fprintf('  %10.2f', fy); end
            if isnan(fz), fprintf('  %10s', '—'); else, fprintf('  %10.2f', fz); end
        end
        fprintf('\n');
    end
end

fprintf('\n[Analiz tamamlandı]\n\n');

end  % ── ana fonksiyon sonu


% ======================================================================
%  YEREL YARDIMCI FONKSİYONLAR
% ======================================================================

function idx = findInSubset(ch_names, subset_idx, axis_kw)
hits = subset_idx(contains(ch_names(subset_idx), axis_kw, 'IgnoreCase', true));
idx  = [];
if ~isempty(hits), idx = hits(1); end
end

function row = getRowSync(data_mat, ch_idx, n_avail, i_start)
if isempty(ch_idx)
    row = zeros(n_avail, 1); return
end
full_row = double(data_mat(ch_idx(1), :))';
n_full   = numel(full_row);
i_end    = min(i_start + n_avail - 1, n_full);
n_actual = i_end - i_start + 1;
row      = zeros(n_avail, 1);
if n_actual > 0
    seg = full_row(i_start:i_end);
    seg(isnan(seg)) = 0;
    row(1:n_actual) = seg;
end
end

function row = getRow(data_mat, ch_idx, N_samp) %#ok<DEFNU>
if isempty(ch_idx)
    row = zeros(N_samp, 1);
else
    row = double(data_mat(ch_idx(1), :))';
    row(isnan(row)) = 0;
end
end

function fs_val = get_ch_fs(fs_arr, ch_idx, fallback)
if isempty(ch_idx), fs_val = fallback;
else,               fs_val = fs_arr(ch_idx(1));
end
if fs_val <= 0, fs_val = fallback; end
end

function seg_out = fill_gaps_1d(seg, fs, gap_max_s, zero_thresh, zero_min_s)
seg_out       = double(seg(:));
N             = numel(seg_out);
if N < 2, return; end
gap_max_samp  = max(1, round(gap_max_s  * fs));
zero_min_samp = max(1, round(zero_min_s * fs));

% Uzun sıfır bloklarını NaN'a çevir
i = 1;
while i <= N
    if ~isnan(seg_out(i)) && abs(seg_out(i)) < zero_thresh
        j = i+1;
        while j <= N && ~isnan(seg_out(j)) && abs(seg_out(j)) < zero_thresh, j=j+1; end
        if (j-i) >= zero_min_samp, seg_out(i:j-1) = NaN; end
        i = j;
    else, i = i+1; end
end

% NaN bloklarını doldur
nan_mask   = isnan(seg_out);
if ~any(nan_mask), return; end
nan_starts = find(diff([0; nan_mask(:)]) ==  1);
nan_ends   = find(diff([nan_mask(:); 0]) == -1);

for b = 1:numel(nan_starts)
    s = nan_starts(b); e = nan_ends(b);
    block_len = e - s + 1;
    left = s-1; right = e+1;
    if left < 1 && right <= N
        seg_out(s:e) = seg_out(right);
    elseif right > N && left >= 1
        seg_out(s:e) = seg_out(left);
    elseif left >= 1 && right <= N
        if block_len <= gap_max_samp
            iv = linspace(seg_out(left), seg_out(right), block_len+2);
            seg_out(s:e) = iv(2:end-1);
        else
            seg_out(s:e) = (seg_out(left)+seg_out(right))/2;
        end
    end
end
end

function s = idx2str(idx)
if isempty(idx), s = '–'; else, s = num2str(idx(1)); end
end
