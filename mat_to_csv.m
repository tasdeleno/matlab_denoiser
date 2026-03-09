function mat_to_csv(mat_file, out_dir, channel_filter)
% =========================================================================
% MAT_TO_CSV  —  Delsys .mat dosyasını CSV'ye dönüştürür
% =========================================================================
%
% Delsys Trigno Lab / Avanti standart export formatını okur:
%   Channels : [1×N] string — kanal adları
%   Fs       : [N×1] double — her kanal için örnekleme frekansı (Hz)
%   Time     : [N×M] double — zaman vektörleri (her satır = 1 kanal)
%   Data     : [N×M] double — sinyal değerleri (her satır = 1 kanal)
%
% KULLANIM:
%   mat_to_csv                             % dosya seçme diyaloğu
%   mat_to_csv('veri.mat')                 % tüm kanallar
%   mat_to_csv('veri.mat', 'C:\cikis')    % çıkış klasörü belirt
%   mat_to_csv('veri.mat', [], 'GYRO')    % sadece GYRO kanalları
%   mat_to_csv('veri.mat', [], 'EMG')     % sadece EMG kanalları
%   mat_to_csv('veri.mat', [], 'ACC')     % sadece ACC kanalları
%
% Filtre örnekleri: 'GYRO', 'GYRO.X', 'EMG', 'ACC', 'L LATISSIMUS'
% Büyük/küçük harf duyarlı değil.
%
% ÇIKTI:
%   Her seçilen kanal için ayrı bir CSV dosyası:
%   <sensor_adi>_<kanal_tipi>_Fs<fs>Hz.csv
%   Format: zaman (s), sinyal değeri
%
% NOT: Bu dosyadaki 'Time' değişkeni zaman eksenini içerir.
%      Sinyal verisi 'Data' değişkeninde olmalıdır.
%      Bu dosyada Data yoksa Delsys'ten yeniden export gerekir.
%
% =========================================================================

narginchk(0, 3);

% ─── 1. Dosya seçimi ────────────────────────────────────────────────────
if nargin < 1 || isempty(mat_file)
    [f, p] = uigetfile({'*.mat','MATLAB Dosyası (*.mat)'}, ...
                        'Delsys .mat dosyasını seçin');
    if isequal(f, 0), fprintf('İptal edildi.\n'); return; end
    mat_file = fullfile(p, f);
end
if ~isfile(mat_file)
    error('[mat_to_csv] Dosya bulunamadı: %s', mat_file);
end

% ─── 2. Çıkış klasörü ───────────────────────────────────────────────────
if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(mat_file);
end
if ~isfolder(out_dir), mkdir(out_dir); end

% ─── 3. Kanal filtresi ──────────────────────────────────────────────────
if nargin < 3 || isempty(channel_filter)
    channel_filter = '';  % tüm kanallar
end

% ─── 4. .mat yükle ──────────────────────────────────────────────────────
fprintf('\n[mat_to_csv] ======================================\n');
fprintf('[mat_to_csv] Dosya: %s\n', mat_file);
fprintf('[mat_to_csv] ======================================\n');

S = load(mat_file);
vars = fieldnames(S);
fprintf('[mat_to_csv] Değişkenler: %s\n', strjoin(vars, ', '));

% ─── 5. Delsys formatı kontrolü ─────────────────────────────────────────
has_channels = isfield(S, 'Channels');
has_fs       = isfield(S, 'Fs');
has_time     = isfield(S, 'Time');
has_data     = isfield(S, 'Data');

if ~has_channels || ~has_fs
    error('[mat_to_csv] Bu dosya Delsys formatında değil (Channels ve Fs eksik).');
end

% Channels: string array veya cell array → string array'e çevir
Channels = S.Channels;
if iscell(Channels), Channels = string(Channels); end
Channels = Channels(:);  % sütun vektörü
N = numel(Channels);

% Fs
Fs = double(S.Fs(:));
if numel(Fs) == 1, Fs = repmat(Fs, N, 1); end

fprintf('[mat_to_csv] Kanal sayısı: %d\n', N);
fprintf('[mat_to_csv] Fs aralığı: %.1f – %.1f Hz\n', min(Fs), max(Fs));

% ─── 6. Data kontrolü ───────────────────────────────────────────────────
if ~has_data
    fprintf('\n[mat_to_csv] ⚠ UYARI: Bu dosyada "Data" değişkeni BULUNAMADI!\n');
    fprintf('[mat_to_csv]   Dosyada yalnızca zaman vektörleri (Time) var.\n');
    fprintf('[mat_to_csv]   Delsys Lab''dan yeniden export yapın:\n');
    fprintf('[mat_to_csv]     1. Delsys Trigno Lab''ı açın\n');
    fprintf('[mat_to_csv]     2. Kayıtlı veriyi yükleyin\n');
    fprintf('[mat_to_csv]     3. File → Export → MATLAB (.mat)\n');
    fprintf('[mat_to_csv]     4. "Include Signal Data" seçili olsun\n');
    fprintf('[mat_to_csv]   Alternatif: Diğer çalışma dosyalarına bakın.\n\n');

    % Sadece kanal listesini yazdır
    fprintf('[mat_to_csv] Dosyadaki kanallar:\n');
    for i = 1:N
        fprintf('  [%2d] %-45s  Fs=%.1f Hz\n', i, Channels(i), Fs(i));
    end
    return;
end

% ─── 7. Kanal seçimi ────────────────────────────────────────────────────
Data = S.Data;
if has_time
    Time = S.Time;
else
    % Zaman vektörünü Fs'ten oluştur
    [~, M] = size(Data);
    Time = zeros(N, M);
    for i = 1:N
        Time(i, :) = (0:M-1) / Fs(i);
    end
end

% Filtre uygula
if isempty(channel_filter)
    sel_idx = 1:N;
else
    mask = contains(Channels, channel_filter, 'IgnoreCase', true);
    sel_idx = find(mask);
    if isempty(sel_idx)
        fprintf('[mat_to_csv] ⚠ "%s" ile eşleşen kanal bulunamadı.\n', channel_filter);
        fprintf('[mat_to_csv] Mevcut kanal tipleri:\n');
        types = unique(extractAfter(Channels, ': '));
        for t = types', fprintf('  %s\n', t); end
        return;
    end
end

fprintf('[mat_to_csv] Seçilen kanal sayısı: %d\n', numel(sel_idx));

% ─── 8. CSV dışa aktar ──────────────────────────────────────────────────
[~, base_name] = fileparts(mat_file);
saved_files = {};

for i = sel_idx(:)'
    ch_name = Channels(i);
    fs_i    = Fs(i);

    % Güvenli dosya adı oluştur
    safe_name = regexprep(ch_name, '[^\w\d]', '_');
    safe_name = regexprep(safe_name, '_+', '_');
    safe_name = strtrim(strtrim(safe_name), '_');
    fname_out = sprintf('%s_%s_Fs%dHz.csv', base_name, safe_name, round(fs_i));
    fpath_out = fullfile(out_dir, fname_out);

    % Geçerli veri uzunluğunu bul (NaN veya sıfır padding'i kesmek için)
    t_row = Time(i, :);
    d_row = Data(i, :);

    % Son geçerli indeksi bul
    last_valid = find(~isnan(d_row) & ~isnan(t_row), 1, 'last');
    if isempty(last_valid)
        fprintf('  [%2d] %-45s  → Veri yok (atlandı)\n', i, ch_name);
        continue;
    end
    t_row = t_row(1:last_valid);
    d_row = d_row(1:last_valid);

    % CSV yaz
    T = array2table([t_row(:), d_row(:)], 'VariableNames', {'Zaman_s', 'Sinyal'});
    writetable(T, fpath_out);

    saved_files{end+1} = fpath_out; %#ok<AGROW>
    fprintf('  [%2d] %-45s  %5d örnek  Fs=%.1f Hz  → %s\n', ...
            i, ch_name, last_valid, fs_i, fname_out);
end

% ─── 9. Özet ────────────────────────────────────────────────────────────
fprintf('\n[mat_to_csv] ✓ %d CSV dosyası kaydedildi → %s\n\n', ...
        numel(saved_files), out_dir);
fprintf('[mat_to_csv] DelsysNoiseMaster''a yüklemek için:\n');
fprintf('  → HTML: Jiroskop sekmesinde "CSV Yükle" → ilgili dosyayı seç\n');
fprintf('  → MATLAB: DelsysNoiseMaster komutunu çalıştır\n\n');

end  % function


% =========================================================================
% YARDIMCI: Seçili kanalları listele (sadece görüntüleme)
% =========================================================================
function list_channels(mat_file, filter_str)
% Kullanım: list_channels('veri.mat', 'GYRO')

if nargin < 1
    [f,p] = uigetfile('*.mat');
    if isequal(f,0), return; end
    mat_file = fullfile(p,f);
end
if nargin < 2, filter_str = ''; end

S = load(mat_file);
if ~isfield(S,'Channels'), disp('Channels değişkeni bulunamadı.'); return; end

Channels = string(S.Channels(:));
Fs = double(S.Fs(:));
has_data = isfield(S, 'Data');

fprintf('\nDosya: %s\n', mat_file);
fprintf('Data değişkeni: %s\n', ternary(has_data, '✓ var', '⚠ YOK'));
fprintf('%-4s  %-50s  %8s\n', '#', 'Kanal Adı', 'Fs (Hz)');
fprintf('%s\n', repmat('-', 1, 66));

for i = 1:numel(Channels)
    if isempty(filter_str) || contains(Channels(i), filter_str, 'IgnoreCase', true)
        fprintf('%-4d  %-50s  %8.1f\n', i, Channels(i), Fs(i));
    end
end
fprintf('\n');
end

function r = ternary(cond, a, b)
    if cond, r = a; else, r = b; end
end
