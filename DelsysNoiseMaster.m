classdef DelsysNoiseMaster < matlab.apps.AppBase
% =========================================================================
%  DELSYS NOISE MASTER — Gelişmiş EMG Gürültü Giderme Uygulaması
%  Versiyon : 1.1
%  Gereklilik: MATLAB R2019b+, Signal Processing Toolbox
%              (Wavelet için: Wavelet Toolbox)
%
%  ÇALIŞTIRMA:
%    >> DelsysNoiseMaster
%    (App Designer değil, MATLAB Command Window veya script'ten çağırın)
%
%  SORUNLAR VE DÜZELTMELER (v1.0 → v1.1):
%    - Dosya formatı hatası: .mlapp → .m olarak düzeltildi
%    - Atanmamış property bildirimleri temizlendi
%    - Kanal değiştirme gerçekten çalışıyor (TumKanallar ile)
%    - Slider hareketi artık filtrelemeyi tetiklemiyor (UI donması giderildi)
%    - Fs düzenlenebilir alan eklendi (başlıksız CSV için)
%    - Daha iyi hata mesajları ve durum bilgisi
% =========================================================================

    % =====================================================================
    %  UI BİLEŞEN PROPERTY'LERİ  (sadece gerçekten atananlar)
    % =====================================================================
    properties (Access = public)
        UIFigure                matlab.ui.Figure

        % Ana tab grubu
        TabGroup                matlab.ui.container.TabGroup
        VeriIslemTab            matlab.ui.container.Tab
        SentetikTab             matlab.ui.container.Tab

        % == TAB 1: VERİ İŞLEME ==
        DosyaYukleButton        matlab.ui.control.Button
        DosyaAdiLabel           matlab.ui.control.Label
        KanalSecDD              matlab.ui.control.DropDown
        OrneklemeDegLabel       matlab.ui.control.Label
        FsEditField             matlab.ui.control.NumericEditField

        FiltreTipiDD            matlab.ui.control.DropDown
        BantPassGrubu           matlab.ui.container.Panel
        DusukKesmeSlider        matlab.ui.control.Slider
        DusukKesmeEditField     matlab.ui.control.NumericEditField
        YuksekKesmeSlider       matlab.ui.control.Slider
        YuksekKesmeEditField    matlab.ui.control.NumericEditField
        NotchGrubu              matlab.ui.container.Panel
        NotchFreqDD             matlab.ui.control.DropDown
        NotchQSlider            matlab.ui.control.Slider
        NotchQEditField         matlab.ui.control.NumericEditField
        WaveletGrubu            matlab.ui.container.Panel
        WaveletTipDD            matlab.ui.control.DropDown
        WaveletSeviyeSpinner    matlab.ui.control.Spinner

        FiltreUygButton         matlab.ui.control.Button
        ExportCSVButton         matlab.ui.control.Button
        ExportMATButton         matlab.ui.control.Button

        SNRDegLabel             matlab.ui.control.Label
        RMSHamDegLabel          matlab.ui.control.Label
        RMSFiltDegLabel         matlab.ui.control.Label
        MedFreqHamDegLabel      matlab.ui.control.Label
        MedFreqFiltDegLabel     matlab.ui.control.Label

        HamSignalAxes           matlab.ui.control.UIAxes
        FiltSignalAxes          matlab.ui.control.UIAxes
        PSDAxes                 matlab.ui.control.UIAxes

        % == TAB 2: SENTETİK ==
        SuresiSlider            matlab.ui.control.Slider
        SuresiEditField         matlab.ui.control.NumericEditField
        OrnFsEditField          matlab.ui.control.NumericEditField
        GurultuSlider           matlab.ui.control.Slider
        GurultuEditField        matlab.ui.control.NumericEditField
        Seb50HzCheck            matlab.ui.control.CheckBox
        BaselineCheck           matlab.ui.control.CheckBox
        SenFiltreTipiDD         matlab.ui.control.DropDown
        SenFiltreUygButton      matlab.ui.control.Button
        SentetikOlusturButton   matlab.ui.control.Button

        SenSNRDegLabel          matlab.ui.control.Label
        SenRMSDegLabel          matlab.ui.control.Label
        SenMFDegLabel           matlab.ui.control.Label

        SenHamAxes              matlab.ui.control.UIAxes
        SenFiltAxes             matlab.ui.control.UIAxes
        SenPSDAxes              matlab.ui.control.UIAxes

        % Ortak
        DurumuLabel             matlab.ui.control.Label
    end

    % =====================================================================
    %  VERİ PROPERTY'LERİ
    % =====================================================================
    properties (Access = private)
        TumKanallar         double      % Tüm kanallar [N × K]
        HamSinyal           double      % Aktif kanal (sütun vektörü)
        FiltreliSinyal      double
        ZamanVektoru        double
        OrneklemeFrekans    double = 2000
        KanalAdlari         cell   = {}
        AktifKanalIdx       int32  = 1

        SenHamSinyal        double
        SenFiltSinyal       double
        SenZaman            double
        SenFs               double = 2000
        SenTemizSinyal      double

        FiltreUygulandiMi   logical = false
    end

    % =====================================================================
    %  YARDIMCI METODLAR (private)
    % =====================================================================
    methods (Access = private)

        % -----------------------------------------------------------------
        function updateStatus(app, msg, tip)
            if nargin < 3, tip = 'bilgi'; end
            switch tip
                case 'hata'
                    app.DurumuLabel.Text = ['  ✕  ' msg];
                    app.DurumuLabel.FontColor     = [0.72 0.05 0.05];
                    app.DurumuLabel.BackgroundColor = [0.98 0.90 0.90];
                case 'uyari'
                    app.DurumuLabel.Text = ['  ⚠  ' msg];
                    app.DurumuLabel.FontColor     = [0.60 0.38 0.00];
                    app.DurumuLabel.BackgroundColor = [0.98 0.95 0.86];
                otherwise
                    app.DurumuLabel.Text = ['  ✔  ' msg];
                    app.DurumuLabel.FontColor     = [0.04 0.48 0.04];
                    app.DurumuLabel.BackgroundColor = [0.88 0.97 0.88];
            end
            drawnow limitrate;
        end

        % -----------------------------------------------------------------
        function guncelleFiltreGorunu(app)
            tip = app.FiltreTipiDD.Value;
            app.BantPassGrubu.Visible = strcmp(tip, 'Butterworth (Bandpass)');
            app.NotchGrubu.Visible    = strcmp(tip, 'Notch (50/60 Hz)');
            app.WaveletGrubu.Visible  = strcmp(tip, 'Wavelet (wdenoise)');
        end

        % -----------------------------------------------------------------
        function cizHamSinyal(app)
            cla(app.HamSignalAxes);
            if isempty(app.HamSinyal), return; end
            plot(app.HamSignalAxes, app.ZamanVektoru, app.HamSinyal, ...
                'Color', [0.18 0.42 0.82], 'LineWidth', 0.8);
            xlabel(app.HamSignalAxes, 'Zaman (s)');
            ylabel(app.HamSignalAxes, 'Genlik');
            title(app.HamSignalAxes, ...
                sprintf('Ham EMG Sinyali  —  Kanal %d  |  Fs = %d Hz  |  %d örnek', ...
                app.AktifKanalIdx, app.OrneklemeFrekans, length(app.HamSinyal)));
            grid(app.HamSignalAxes, 'on');
            app.HamSignalAxes.GridAlpha = 0.22;
        end

        % -----------------------------------------------------------------
        function cizFiltreliSinyal(app)
            cla(app.FiltSignalAxes);
            if isempty(app.FiltreliSinyal), return; end
            plot(app.FiltSignalAxes, app.ZamanVektoru, app.HamSinyal, ...
                'Color', [0.72 0.72 0.76], 'LineWidth', 0.5, 'DisplayName', 'Ham');
            hold(app.FiltSignalAxes, 'on');
            plot(app.FiltSignalAxes, app.ZamanVektoru, app.FiltreliSinyal, ...
                'Color', [0.85 0.22 0.08], 'LineWidth', 1.3, 'DisplayName', 'Filtrelenmiş');
            hold(app.FiltSignalAxes, 'off');
            legend(app.FiltSignalAxes, 'Location', 'best', 'FontSize', 8);
            xlabel(app.FiltSignalAxes, 'Zaman (s)');
            ylabel(app.FiltSignalAxes, 'Genlik');
            title(app.FiltSignalAxes, ...
                sprintf('Ham & Filtrelenmiş  [%s]', app.FiltreTipiDD.Value));
            grid(app.FiltSignalAxes, 'on');
            app.FiltSignalAxes.GridAlpha = 0.22;
        end

        % -----------------------------------------------------------------
        function cizPSD(app)
            cla(app.PSDAxes);
            if isempty(app.HamSinyal), return; end
            fs  = app.OrneklemeFrekans;
            win = min(round(length(app.HamSinyal)/4), 1024);
            [pxx_h, f_h] = pwelch(app.HamSinyal, win, [], [], fs);
            semilogy(app.PSDAxes, f_h, pxx_h, ...
                'Color', [0.18 0.42 0.82], 'LineWidth', 1, 'DisplayName', 'Ham');
            hold(app.PSDAxes, 'on');
            if ~isempty(app.FiltreliSinyal)
                [pxx_f, f_f] = pwelch(app.FiltreliSinyal, win, [], [], fs);
                semilogy(app.PSDAxes, f_f, pxx_f, ...
                    'Color', [0.85 0.22 0.08], 'LineWidth', 1, 'DisplayName', 'Filtrelenmiş');
            end
            hold(app.PSDAxes, 'off');
            legend(app.PSDAxes, 'Location', 'best', 'FontSize', 8);
            xlabel(app.PSDAxes, 'Frekans (Hz)');
            ylabel(app.PSDAxes, 'Güç Yoğunluğu');
            title(app.PSDAxes, 'Güç Spektral Yoğunluğu — Welch Yöntemi');
            grid(app.PSDAxes, 'on');
            xlim(app.PSDAxes, [0 fs/2]);
        end

        % -----------------------------------------------------------------
        function hesaplaMetrikler(app)
            if isempty(app.HamSinyal), return; end
            fs = app.OrneklemeFrekans;

            app.RMSHamDegLabel.Text     = sprintf('%.5f', rms(app.HamSinyal));
            app.MedFreqHamDegLabel.Text = sprintf('%.1f Hz', ...
                medianFreqLocal(app.HamSinyal, fs));

            if ~isempty(app.FiltreliSinyal) && app.FiltreUygulandiMi
                app.RMSFiltDegLabel.Text     = sprintf('%.5f', rms(app.FiltreliSinyal));
                app.MedFreqFiltDegLabel.Text = sprintf('%.1f Hz', ...
                    medianFreqLocal(app.FiltreliSinyal, fs));

                d  = app.HamSinyal - app.FiltreliSinyal;
                ps = mean(app.FiltreliSinyal.^2);
                pn = mean(d.^2);
                if pn > 0
                    snr_db = 10 * log10(ps / pn);
                    app.SNRDegLabel.Text = sprintf('%.2f dB', snr_db);
                else
                    app.SNRDegLabel.Text = 'Inf dB';
                end
            else
                app.SNRDegLabel.Text     = '—';
                app.RMSFiltDegLabel.Text = '—';
                app.MedFreqFiltDegLabel.Text = '—';
            end
        end

        % -----------------------------------------------------------------
        function filtreUygula(app)
            if isempty(app.HamSinyal)
                updateStatus(app, 'Önce bir dosya yükleyin!', 'uyari');
                return;
            end
            tip = app.FiltreTipiDD.Value;
            fs  = app.OrneklemeFrekans;
            updateStatus(app, ['Filtre uygulanıyor: ' tip ' …']);
            try
                switch tip
                    case 'Butterworth (Bandpass)'
                        fc_low  = app.DusukKesmeEditField.Value;
                        fc_high = app.YuksekKesmeEditField.Value;
                        params  = struct('low', fc_low, 'high', fc_high, 'order', 4);
                        app.FiltreliSinyal = advanced_filter(app.HamSinyal, fs, ...
                            'butterworth', params);

                    case 'Notch (50/60 Hz)'
                        f_notch = str2double(app.NotchFreqDD.Value);
                        q_val   = app.NotchQEditField.Value;
                        params  = struct('f_notch', f_notch, 'Q', q_val);
                        app.FiltreliSinyal = advanced_filter(app.HamSinyal, fs, ...
                            'notch', params);

                    case 'Wavelet (wdenoise)'
                        wname  = app.WaveletTipDD.Value;
                        level  = app.WaveletSeviyeSpinner.Value;
                        params = struct('wavelet', wname, 'level', level);
                        app.FiltreliSinyal = advanced_filter(app.HamSinyal, fs, ...
                            'wavelet', params);
                end
                app.FiltreUygulandiMi = true;
                cizFiltreliSinyal(app);
                cizPSD(app);
                hesaplaMetrikler(app);
                updateStatus(app, sprintf('Filtre uygulandı  |  %s  |  Fs=%d Hz  |  %d örnek', ...
                    tip, fs, length(app.HamSinyal)));
            catch ME
                updateStatus(app, ME.message, 'hata');
            end
        end

        % -----------------------------------------------------------------
        function kanalYukle(app, idx)
            if isempty(app.TumKanallar) || idx < 1 || idx > size(app.TumKanallar, 2)
                return;
            end
            app.HamSinyal          = app.TumKanallar(:, idx);
            app.FiltreliSinyal     = [];
            app.FiltreUygulandiMi  = false;
            app.AktifKanalIdx      = int32(idx);
            cizHamSinyal(app);
            cla(app.FiltSignalAxes);
            cizPSD(app);
            hesaplaMetrikler(app);
        end

        % -----------------------------------------------------------------
        function sentetikCiz(app)
            % --- Ham sinyal ---
            cla(app.SenHamAxes);
            if isempty(app.SenHamSinyal), return; end
            plot(app.SenHamAxes, app.SenZaman, app.SenHamSinyal, ...
                'Color', [0.18 0.42 0.82], 'LineWidth', 0.7, 'DisplayName', 'Gürültülü');
            if ~isempty(app.SenTemizSinyal)
                hold(app.SenHamAxes, 'on');
                plot(app.SenHamAxes, app.SenZaman, app.SenTemizSinyal, ...
                    'Color', [0 0.68 0.18], 'LineWidth', 1.2, ...
                    'LineStyle', '--', 'DisplayName', 'Temiz Ref');
                hold(app.SenHamAxes, 'off');
                legend(app.SenHamAxes, 'Location', 'best', 'FontSize', 8);
            end
            xlabel(app.SenHamAxes, 'Zaman (s)');
            ylabel(app.SenHamAxes, 'Genlik');
            title(app.SenHamAxes, 'Sentetik Ham EMG  —  Gürültülü + Temiz Referans');
            grid(app.SenHamAxes, 'on');

            % --- Filtrelenmiş sinyal ---
            cla(app.SenFiltAxes);
            if ~isempty(app.SenFiltSinyal)
                if ~isempty(app.SenTemizSinyal)
                    plot(app.SenFiltAxes, app.SenZaman, app.SenTemizSinyal, ...
                        'Color', [0 0.68 0.18], 'LineWidth', 1, ...
                        'LineStyle', '--', 'DisplayName', 'Temiz');
                    hold(app.SenFiltAxes, 'on');
                end
                plot(app.SenFiltAxes, app.SenZaman, app.SenFiltSinyal, ...
                    'Color', [0.85 0.22 0.08], 'LineWidth', 1.3, 'DisplayName', 'Filtrelenmiş');
                if ~isempty(app.SenTemizSinyal)
                    hold(app.SenFiltAxes, 'off');
                    legend(app.SenFiltAxes, 'Location', 'best', 'FontSize', 8);
                end
                xlabel(app.SenFiltAxes, 'Zaman (s)');
                ylabel(app.SenFiltAxes, 'Genlik');
                title(app.SenFiltAxes, sprintf('Filtrelenmiş  [%s]', app.SenFiltreTipiDD.Value));
                grid(app.SenFiltAxes, 'on');
            end

            % --- PSD ---
            cla(app.SenPSDAxes);
            win = min(round(length(app.SenHamSinyal)/4), 1024);
            [pxx, f] = pwelch(app.SenHamSinyal, win, [], [], app.SenFs);
            semilogy(app.SenPSDAxes, f, pxx, ...
                'Color', [0.18 0.42 0.82], 'LineWidth', 1, 'DisplayName', 'Ham');
            hold(app.SenPSDAxes, 'on');
            if ~isempty(app.SenFiltSinyal)
                [pxx_f, f_f] = pwelch(app.SenFiltSinyal, win, [], [], app.SenFs);
                semilogy(app.SenPSDAxes, f_f, pxx_f, ...
                    'Color', [0.85 0.22 0.08], 'LineWidth', 1, 'DisplayName', 'Filtrelenmiş');
            end
            hold(app.SenPSDAxes, 'off');
            legend(app.SenPSDAxes, 'Location', 'best', 'FontSize', 8);
            xlabel(app.SenPSDAxes, 'Frekans (Hz)');
            ylabel(app.SenPSDAxes, 'Güç Yoğunluğu');
            title(app.SenPSDAxes, 'Güç Spektral Yoğunluğu — Welch');
            grid(app.SenPSDAxes, 'on');
            xlim(app.SenPSDAxes, [0 app.SenFs/2]);
        end

    end % private methods

    % =====================================================================
    %  CALLBACK METODLAR
    % =====================================================================
    methods (Access = private)

        % ----- Dosya Yükleme -----
        function DosyaYukleButtonPushed(app, ~)
            [fname, fpath] = uigetfile( ...
                {'*.csv','CSV Dosyası (*.csv)'; ...
                 '*.mat','MATLAB Dosyası (*.mat)'; ...
                 '*.*','Tüm Dosyalar'}, ...
                'EMG Dosyası Seç');
            if isequal(fname, 0), return; end

            fullpath = fullfile(fpath, fname);
            updateStatus(app, ['Yükleniyor: ' fname ' …']);

            try
                [~, ~, ext] = fileparts(fname);
                sigData = [];
                t_col   = [];

                if strcmpi(ext, '.csv')
                    try
                        T = readtable(fullpath, 'VariableNamingRule', 'preserve');
                        numMask = varfun(@isnumeric, T, 'OutputFormat', 'uniform');
                        numData = T{:, numMask};
                        colNames = T.Properties.VariableNames(numMask);
                    catch
                        numData  = readmatrix(fullpath);
                        colNames = arrayfun(@(x) sprintf('Kanal_%d', x), ...
                            1:size(numData,2), 'UniformOutput', false);
                    end
                    % İlk sütun zaman ekseni mi?
                    if size(numData,2) > 1 && all(diff(numData(:,1)) > 0)
                        t_col   = numData(:,1);
                        sigData = numData(:, 2:end);
                        dt      = mean(diff(t_col));
                        app.OrneklemeFrekans = round(1/dt);
                        app.KanalAdlari      = colNames(2:end);
                    else
                        sigData         = numData;
                        app.KanalAdlari = colNames;
                    end

                elseif strcmpi(ext, '.mat')
                    S      = load(fullpath);
                    fields = fieldnames(S);
                    dataField = '';
                    fsField   = '';
                    for ii = 1:numel(fields)
                        fn = lower(fields{ii});
                        if any(strcmp(fn, {'data','emg','signal','signals','y','raw','x'}))
                            dataField = fields{ii};
                        end
                        if any(strcmp(fn, {'fs','samplerate','sr','fsamp','frequency'}))
                            fsField = fields{ii};
                        end
                    end
                    if isempty(dataField)
                        for ii = 1:numel(fields)
                            if isnumeric(S.(fields{ii})) && ~isscalar(S.(fields{ii}))
                                dataField = fields{ii}; break;
                            end
                        end
                    end
                    if isempty(dataField)
                        error('MAT dosyasında uygun sinyal alanı bulunamadı.');
                    end
                    sigData = double(S.(dataField));
                    if ~isempty(fsField)
                        app.OrneklemeFrekans = double(S.(fsField));
                    end
                    app.KanalAdlari = arrayfun(@(x) sprintf('Kanal_%d',x), ...
                        1:size(sigData,2), 'UniformOutput', false);

                else
                    error('Desteklenmeyen format: %s', ext);
                end

                % Satır = örnek, sütun = kanal
                if size(sigData,1) < size(sigData,2)
                    sigData = sigData';
                end

                N  = size(sigData,1);
                fs = app.OrneklemeFrekans;

                if isempty(t_col)
                    app.ZamanVektoru = (0:N-1)' / fs;
                else
                    app.ZamanVektoru = t_col;
                end

                app.TumKanallar       = sigData;
                app.FiltreliSinyal    = [];
                app.FiltreUygulandiMi = false;

                % UI güncelle
                app.OrneklemeDegLabel.Text = sprintf('%d Hz', fs);
                app.FsEditField.Value      = fs;
                app.DosyaAdiLabel.Text     = fname;

                % Kanal dropdown
                if ~isempty(app.KanalAdlari)
                    app.KanalSecDD.Items     = app.KanalAdlari;
                    app.KanalSecDD.ItemsData = num2cell(1:numel(app.KanalAdlari));
                    app.KanalSecDD.Value     = 1;
                end

                % İlk kanalı yükle ve çiz
                kanalYukle(app, 1);

                updateStatus(app, sprintf('%s  |  %d örnek  |  %d kanal  |  Fs = %d Hz', ...
                    fname, N, size(sigData,2), fs));

            catch ME
                updateStatus(app, ME.message, 'hata');
            end
        end

        % ----- Kanal Değişimi -----
        function KanalSecDDValueChanged(app, ~)
            if isempty(app.TumKanallar), return; end
            idx = app.KanalSecDD.Value;
            if ~isnumeric(idx), return; end
            kanalYukle(app, idx);
            updateStatus(app, sprintf('Kanal %d yüklendi', idx));
        end

        % ----- Fs Düzenleme -----
        function FsEditFieldValueChanged(app, ~)
            fs = app.FsEditField.Value;
            app.OrneklemeFrekans       = fs;
            app.OrneklemeDegLabel.Text = sprintf('%d Hz', round(fs));
            if ~isempty(app.HamSinyal)
                N = length(app.HamSinyal);
                app.ZamanVektoru = (0:N-1)' / fs;
                cizHamSinyal(app);
                cizPSD(app);
                hesaplaMetrikler(app);
            end
        end

        % ----- Filtre Tipi -----
        function FiltreTipiDDValueChanged(app, ~)
            guncelleFiltreGorunu(app);
        end

        % ----- Butterworth Sliderları -----
        function DusukKesmeSliderValueChanged(app, ~)
            val = round(app.DusukKesmeSlider.Value);
            val = min(val, app.YuksekKesmeEditField.Value - 1);
            app.DusukKesmeSlider.Value    = val;
            app.DusukKesmeEditField.Value = val;
        end

        function DusukKesmeEditFieldValueChanged(app, ~)
            val = max(1, min(app.DusukKesmeEditField.Value, ...
                app.YuksekKesmeEditField.Value - 1));
            app.DusukKesmeEditField.Value = val;
            app.DusukKesmeSlider.Value    = val;
        end

        function YuksekKesmeSliderValueChanged(app, ~)
            val = round(app.YuksekKesmeSlider.Value);
            val = max(val, app.DusukKesmeEditField.Value + 1);
            app.YuksekKesmeSlider.Value    = val;
            app.YuksekKesmeEditField.Value = val;
        end

        function YuksekKesmeEditFieldValueChanged(app, ~)
            val = max(app.DusukKesmeEditField.Value + 1, ...
                min(app.YuksekKesmeEditField.Value, ...
                    app.OrneklemeFrekans/2 - 1));
            app.YuksekKesmeEditField.Value = val;
            app.YuksekKesmeSlider.Value    = val;
        end

        % ----- Notch Q Sliderı -----
        function NotchQSliderValueChanged(app, ~)
            app.NotchQEditField.Value = round(app.NotchQSlider.Value);
        end

        function NotchQEditFieldValueChanged(app, ~)
            app.NotchQSlider.Value = app.NotchQEditField.Value;
        end

        % ----- Filtre Uygula -----
        function FiltreUygButtonPushed(app, ~)
            filtreUygula(app);
        end

        % ----- Export CSV -----
        function ExportCSVButtonPushed(app, ~)
            if isempty(app.FiltreliSinyal)
                updateStatus(app, 'Önce filtre uygulayın!', 'uyari');
                return;
            end
            [fname, fpath] = uiputfile('*.csv', 'CSV olarak kaydet', 'filtrelenmis_emg.csv');
            if isequal(fname, 0), return; end
            try
                T = table(app.ZamanVektoru, app.HamSinyal, app.FiltreliSinyal, ...
                    'VariableNames', {'Zaman_s','Ham','Filtrelenmis'});
                writetable(T, fullfile(fpath, fname));
                updateStatus(app, ['CSV kaydedildi  →  ' fname]);
            catch ME
                updateStatus(app, ME.message, 'hata');
            end
        end

        % ----- Export MAT -----
        function ExportMATButtonPushed(app, ~)
            if isempty(app.FiltreliSinyal)
                updateStatus(app, 'Önce filtre uygulayın!', 'uyari');
                return;
            end
            [fname, fpath] = uiputfile('*.mat', 'MAT olarak kaydet', 'filtrelenmis_emg.mat');
            if isequal(fname, 0), return; end
            try
                zaman       = app.ZamanVektoru;       %#ok<NASGU>
                ham         = app.HamSinyal;           %#ok<NASGU>
                filtrelenmis = app.FiltreliSinyal;     %#ok<NASGU>
                fs          = app.OrneklemeFrekans;    %#ok<NASGU>
                filtre_tipi = app.FiltreTipiDD.Value;  %#ok<NASGU>
                save(fullfile(fpath, fname), ...
                    'zaman','ham','filtrelenmis','fs','filtre_tipi');
                updateStatus(app, ['MAT kaydedildi  →  ' fname]);
            catch ME
                updateStatus(app, ME.message, 'hata');
            end
        end

        % ----- Sentetik EMG Oluştur -----
        function SentetikOlusturButtonPushed(app, ~)
            fs      = app.OrnFsEditField.Value;
            sure    = app.SuresiEditField.Value;
            gurultu = app.GurultuEditField.Value / 100;
            add50   = app.Seb50HzCheck.Value;
            addBL   = app.BaselineCheck.Value;
            app.SenFs = fs;

            updateStatus(app, 'Sentetik EMG oluşturuluyor…');
            try
                [ham, temiz, t] = generate_synthetic_emg(fs, sure, gurultu, add50, addBL);
                app.SenHamSinyal   = ham;
                app.SenTemizSinyal = temiz;
                app.SenZaman       = t;
                app.SenFiltSinyal  = [];

                app.SenSNRDegLabel.Text = '—';
                app.SenRMSDegLabel.Text = sprintf('%.5f', rms(ham));
                app.SenMFDegLabel.Text  = sprintf('%.1f Hz', medianFreqLocal(ham, fs));

                sentetikCiz(app);
                updateStatus(app, sprintf( ...
                    'Sentetik EMG oluşturuldu  |  Fs=%d Hz  |  %.1f s  |  %%%d gürültü', ...
                    fs, sure, round(gurultu*100)));
            catch ME
                updateStatus(app, ME.message, 'hata');
            end
        end

        % Süre slider ↔ editfield
        function SuresiSliderValueChanged(app, ~)
            app.SuresiEditField.Value = round(app.SuresiSlider.Value * 10) / 10;
        end
        function SuresiEditFieldValueChanged(app, ~)
            app.SuresiSlider.Value = app.SuresiEditField.Value;
        end

        % Gürültü slider ↔ editfield
        function GurultuSliderValueChanged(app, ~)
            app.GurultuEditField.Value = round(app.GurultuSlider.Value);
        end
        function GurultuEditFieldValueChanged(app, ~)
            app.GurultuSlider.Value = app.GurultuEditField.Value;
        end

        % ----- Sentetik Filtre Uygula -----
        function SenFiltreUygButtonPushed(app, ~)
            if isempty(app.SenHamSinyal)
                updateStatus(app, 'Önce sentetik sinyal oluşturun!', 'uyari');
                return;
            end
            fs  = app.SenFs;
            tip = app.SenFiltreTipiDD.Value;
            updateStatus(app, ['Filtre uygulanıyor: ' tip ' …']);
            try
                switch tip
                    case 'Butterworth (Bandpass)'
                        app.SenFiltSinyal = advanced_filter(app.SenHamSinyal, fs, ...
                            'butterworth', struct('low',20,'high',450,'order',4));
                    case 'Notch (50 Hz)'
                        app.SenFiltSinyal = advanced_filter(app.SenHamSinyal, fs, ...
                            'notch', struct('f_notch',50,'Q',35));
                    case 'Wavelet (db4)'
                        app.SenFiltSinyal = advanced_filter(app.SenHamSinyal, fs, ...
                            'wavelet', struct('wavelet','db4','level',5));
                    case 'Tam Zincir (BP + Notch)'
                        ara = advanced_filter(app.SenHamSinyal, fs, ...
                            'butterworth', struct('low',20,'high',450,'order',4));
                        app.SenFiltSinyal = advanced_filter(ara, fs, ...
                            'notch', struct('f_notch',50,'Q',35));
                end

                app.SenRMSDegLabel.Text = sprintf('%.5f', rms(app.SenFiltSinyal));
                app.SenMFDegLabel.Text  = sprintf('%.1f Hz', ...
                    medianFreqLocal(app.SenFiltSinyal, fs));

                if ~isempty(app.SenTemizSinyal)
                    ps = mean(app.SenTemizSinyal.^2);
                    pn = mean((app.SenFiltSinyal - app.SenTemizSinyal).^2);
                    if pn > 0
                        app.SenSNRDegLabel.Text = sprintf('%.2f dB', 10*log10(ps/pn));
                    else
                        app.SenSNRDegLabel.Text = 'Inf dB';
                    end
                end

                sentetikCiz(app);
                updateStatus(app, sprintf('Filtre uygulandı  [%s]', tip));
            catch ME
                updateStatus(app, ME.message, 'hata');
            end
        end

    end % callback methods

    % =====================================================================
    %  BİLEŞEN OLUŞTURMA
    % =====================================================================
    methods (Access = private)

        function createComponents(app)

            % Ana figür
            app.UIFigure          = uifigure('Visible', 'off');
            app.UIFigure.Position = [80 50 1300 800];
            app.UIFigure.Name     = 'Delsys Noise Master  v1.1';
            app.UIFigure.Color    = [0.93 0.93 0.96];
            app.UIFigure.Resize   = 'on';

            % Başlık
            uilabel(app.UIFigure, ...
                'Text', 'DELSYS NOISE MASTER  ·  EMG Gürültü Giderme & Analiz', ...
                'Position', [18 760 820 30], ...
                'FontSize', 17, 'FontWeight', 'bold', ...
                'FontColor', [0.12 0.20 0.52]);

            % Alt durum çubuğu
            app.DurumuLabel = uilabel(app.UIFigure, ...
                'Text', '  Hazır. Dosya yükleyin veya Sentetik Test sekmesini kullanın.', ...
                'Position', [0 0 1300 26], ...
                'FontSize', 10, 'FontWeight', 'normal', ...
                'FontColor', [0.04 0.48 0.04], ...
                'BackgroundColor', [0.88 0.97 0.88], ...
                'HorizontalAlignment', 'left');

            % Tab Grubu
            app.TabGroup = uitabgroup(app.UIFigure, ...
                'Position', [8 28 1284 728]);

            % =============================================================
            %  TAB 1 — VERİ İŞLEME
            % =============================================================
            app.VeriIslemTab = uitab(app.TabGroup, ...
                'Title', '   Veri İşleme   ');

            % ---------- Sol panel ----------
            SP = uipanel(app.VeriIslemTab, ...
                'BorderType','none', 'Position', [5 5 290 714]);

            % Veri Kaynağı
            uilabel(SP,'Text','VERİ KAYNAĞI','Position',[5 688 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            app.DosyaYukleButton = uibutton(SP,'push', ...
                'Text','  Dosya Yükle  (CSV  /  MAT)', ...
                'Position',[5 654 280 32], ...
                'FontSize',11,'FontWeight','bold', ...
                'BackgroundColor',[0.15 0.35 0.82],'FontColor','white', ...
                'ButtonPushedFcn', createCallbackFcn(app,@DosyaYukleButtonPushed,true));

            app.DosyaAdiLabel = uilabel(SP, ...
                'Text','(dosya seçilmedi)', ...
                'Position',[5 636 280 17],'FontSize',9,'FontColor',[0.50 0.50 0.55]);

            % Kanal seçimi
            uilabel(SP,'Text','Kanal:','Position',[5 610 55 20],'FontSize',9);
            app.KanalSecDD = uidropdown(SP, ...
                'Items',{'(veri yok)'},'Position',[62 610 223 22], ...
                'ValueChangedFcn', createCallbackFcn(app,@KanalSecDDValueChanged,true));

            % Örnekleme Frekansı
            uilabel(SP,'Text','Fs (Hz):','Position',[5 583 60 20],'FontSize',9);
            app.OrneklemeDegLabel = uilabel(SP,'Text','2000 Hz', ...
                'Position',[68 583 78 20],'FontWeight','bold', ...
                'FontColor',[0.05 0.45 0.05],'FontSize',9, ...
                'Tooltip','Dosyadan okunan örnekleme frekansı');
            app.FsEditField = uieditfield(SP,'numeric', ...
                'Value',2000,'Limits',[1 200000], ...
                'Position',[152 583 140 22],'FontSize',9, ...
                'Tooltip','Dosyada zaman sütunu yoksa buradan girebilirsiniz', ...
                'ValueChangedFcn', createCallbackFcn(app,@FsEditFieldValueChanged,true));

            % Ayraç
            uipanel(SP,'BorderType','line','BackgroundColor',[0.72 0.74 0.82], ...
                'Position',[0 574 290 1]);

            % Filtre Ayarları
            uilabel(SP,'Text','FİLTRE AYARLARI','Position',[5 556 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            uilabel(SP,'Text','Filtre Tipi:','Position',[5 534 80 18],'FontSize',9);
            app.FiltreTipiDD = uidropdown(SP, ...
                'Items',{'Butterworth (Bandpass)','Notch (50/60 Hz)','Wavelet (wdenoise)'}, ...
                'Position',[5 510 280 24], ...
                'ValueChangedFcn', createCallbackFcn(app,@FiltreTipiDDValueChanged,true));

            % -- Butterworth paneli --
            PANPOS = [3 382 284 126];
            app.BantPassGrubu = uipanel(SP,'Title','Butterworth Bandpass Parametreleri', ...
                'Position',PANPOS,'FontSize',9,'FontWeight','bold');

            uilabel(app.BantPassGrubu,'Text','Alt Kesme (Hz):', ...
                'Position',[5 92 115 18],'FontSize',9);
            app.DusukKesmeEditField = uieditfield(app.BantPassGrubu,'numeric', ...
                'Value',20,'Limits',[1 498],'Position',[230 92 48 22],'FontSize',9, ...
                'ValueChangedFcn', createCallbackFcn(app,@DusukKesmeEditFieldValueChanged,true));
            app.DusukKesmeSlider = uislider(app.BantPassGrubu, ...
                'Limits',[1 498],'Value',20,'Position',[5 86 270 3], ...
                'ValueChangedFcn', createCallbackFcn(app,@DusukKesmeSliderValueChanged,true));

            uilabel(app.BantPassGrubu,'Text','Üst Kesme (Hz):', ...
                'Position',[5 55 115 18],'FontSize',9);
            app.YuksekKesmeEditField = uieditfield(app.BantPassGrubu,'numeric', ...
                'Value',450,'Limits',[2 499],'Position',[230 55 48 22],'FontSize',9, ...
                'ValueChangedFcn', createCallbackFcn(app,@YuksekKesmeEditFieldValueChanged,true));
            app.YuksekKesmeSlider = uislider(app.BantPassGrubu, ...
                'Limits',[2 499],'Value',450,'Position',[5 49 270 3], ...
                'ValueChangedFcn', createCallbackFcn(app,@YuksekKesmeSliderValueChanged,true));

            uilabel(app.BantPassGrubu,'Text','Standart EMG bandı: 20 – 450 Hz', ...
                'Position',[5 6 270 16],'FontSize',8,'FontColor',[0.52 0.52 0.55]);

            % -- Notch paneli (aynı konumda, kapalı başlar) --
            app.NotchGrubu = uipanel(SP,'Title','Notch Parametreleri', ...
                'Position',PANPOS,'FontSize',9,'FontWeight','bold','Visible','off');

            uilabel(app.NotchGrubu,'Text','Notch Frekansı:', ...
                'Position',[5 92 110 18],'FontSize',9);
            app.NotchFreqDD = uidropdown(app.NotchGrubu, ...
                'Items',{'50','60'},'Value','50','Position',[120 92 80 24],'FontSize',9);
            uilabel(app.NotchGrubu,'Text','Hz','Position',[205 92 28 18],'FontSize',9);

            uilabel(app.NotchGrubu,'Text','Q Faktörü:', ...
                'Position',[5 55 80 18],'FontSize',9);
            app.NotchQEditField = uieditfield(app.NotchGrubu,'numeric', ...
                'Value',35,'Limits',[5 200],'Position',[230 55 48 22],'FontSize',9, ...
                'ValueChangedFcn', createCallbackFcn(app,@NotchQEditFieldValueChanged,true));
            app.NotchQSlider = uislider(app.NotchGrubu, ...
                'Limits',[5 200],'Value',35,'Position',[5 49 270 3], ...
                'ValueChangedFcn', createCallbackFcn(app,@NotchQSliderValueChanged,true));
            uilabel(app.NotchGrubu,'Text','Yüksek Q → daha dar bant', ...
                'Position',[5 6 270 16],'FontSize',8,'FontColor',[0.52 0.52 0.55]);

            % -- Wavelet paneli (aynı konumda, kapalı başlar) --
            app.WaveletGrubu = uipanel(SP,'Title','Wavelet Parametreleri (Wavelet Toolbox)', ...
                'Position',PANPOS,'FontSize',9,'FontWeight','bold','Visible','off');

            uilabel(app.WaveletGrubu,'Text','Wavelet Ailesi:', ...
                'Position',[5 92 110 18],'FontSize',9);
            app.WaveletTipDD = uidropdown(app.WaveletGrubu, ...
                'Items',{'db4','db6','sym4','sym6','coif3'},'Value','db4', ...
                'Position',[5 66 140 24],'FontSize',9);

            uilabel(app.WaveletGrubu,'Text','Ayrışım Seviyesi:', ...
                'Position',[155 92 120 18],'FontSize',9);
            app.WaveletSeviyeSpinner = uispinner(app.WaveletGrubu, ...
                'Value',5,'Limits',[1 10],'Step',1, ...
                'Position',[155 66 120 24],'FontSize',9);
            uilabel(app.WaveletGrubu,'Text','Eşikleme: SURE (otomatik)', ...
                'Position',[5 6 270 16],'FontSize',8,'FontColor',[0.52 0.52 0.55]);

            % Filtre Uygula butonu
            app.FiltreUygButton = uibutton(SP,'push', ...
                'Text','  Filtreyi Uygula', ...
                'Position',[5 347 280 34], ...
                'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.06 0.55 0.16],'FontColor','white', ...
                'ButtonPushedFcn', createCallbackFcn(app,@FiltreUygButtonPushed,true));

            % Ayraç
            uipanel(SP,'BorderType','line','BackgroundColor',[0.72 0.74 0.82], ...
                'Position',[0 337 290 1]);

            % Export
            uilabel(SP,'Text','DIŞA AKTAR','Position',[5 319 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            app.ExportCSVButton = uibutton(SP,'push','Text','  CSV İndir', ...
                'Position',[5 288 138 28], ...
                'BackgroundColor',[0.42 0.28 0.72],'FontColor','white','FontWeight','bold', ...
                'ButtonPushedFcn', createCallbackFcn(app,@ExportCSVButtonPushed,true));
            app.ExportMATButton = uibutton(SP,'push','Text','  MAT İndir', ...
                'Position',[148 288 142 28], ...
                'BackgroundColor',[0.42 0.28 0.72],'FontColor','white','FontWeight','bold', ...
                'ButtonPushedFcn', createCallbackFcn(app,@ExportMATButtonPushed,true));

            % Ayraç
            uipanel(SP,'BorderType','line','BackgroundColor',[0.72 0.74 0.82], ...
                'Position',[0 278 290 1]);

            % Metrikler
            uilabel(SP,'Text','SİNYAL METRİKLERİ','Position',[5 260 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            mkP = uipanel(SP,'BorderType','line','Position',[3 5 284 252]);

            mk_lbl  = {'SNR (dB):','RMS Ham:','RMS Filtrelenmiş:', ...
                       'Median Frekans Ham:','Median Frekans Filt:'};
            mk_tip  = {'Sinyal/Gürültü Oranı (ham - filtrelenmiş)','Ham sinyalin RMS değeri', ...
                       'Filtrelenmiş sinyalin RMS değeri','Ham sinyalin medyan frekansı', ...
                       'Filtrelenmiş sinyalin medyan frekansı'};
            mk_prop = {'SNRDegLabel','RMSHamDegLabel','RMSFiltDegLabel', ...
                       'MedFreqHamDegLabel','MedFreqFiltDegLabel'};

            for mi = 1:5
                ry = 228 - (mi-1)*44;
                uilabel(mkP,'Text',mk_lbl{mi},'Position',[6 ry 145 18], ...
                    'FontSize',9,'FontWeight','bold','Tooltip',mk_tip{mi});
                app.(mk_prop{mi}) = uilabel(mkP,'Text','—', ...
                    'Position',[155 ry 125 18],'FontSize',11, ...
                    'FontColor',[0.72 0.18 0.04],'FontWeight','bold');
            end

            % ---------- Sağ grafik alanı ----------
            RP = uipanel(app.VeriIslemTab,'BorderType','none','Position',[302 5 976 714]);

            app.HamSignalAxes = uiaxes(RP,'Position',[5 488 960 218]);
            title(app.HamSignalAxes,'Ham EMG Sinyali');
            xlabel(app.HamSignalAxes,'Zaman (s)'); ylabel(app.HamSignalAxes,'Genlik');
            grid(app.HamSignalAxes,'on');

            app.FiltSignalAxes = uiaxes(RP,'Position',[5 265 960 218]);
            title(app.FiltSignalAxes,'Ham & Filtrelenmiş Sinyal Karşılaştırması');
            xlabel(app.FiltSignalAxes,'Zaman (s)'); ylabel(app.FiltSignalAxes,'Genlik');
            grid(app.FiltSignalAxes,'on');

            app.PSDAxes = uiaxes(RP,'Position',[5 5 960 252]);
            title(app.PSDAxes,'Güç Spektral Yoğunluğu  —  Welch Yöntemi');
            xlabel(app.PSDAxes,'Frekans (Hz)'); ylabel(app.PSDAxes,'Güç Yoğunluğu');
            grid(app.PSDAxes,'on');

            % =============================================================
            %  TAB 2 — SENTETİK TEST & ANALİZ
            % =============================================================
            app.SentetikTab = uitab(app.TabGroup, ...
                'Title','   Sentetik Test & Analiz   ');

            % ---------- Sol panel ----------
            SS = uipanel(app.SentetikTab,'BorderType','none','Position',[5 5 290 714]);

            uilabel(SS,'Text','SİNYAL PARAMETRELERİ','Position',[5 688 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            uilabel(SS,'Text','Süre (s):','Position',[5 662 80 18],'FontSize',9);
            app.SuresiEditField = uieditfield(SS,'numeric','Value',3,'Limits',[0.5 30], ...
                'Position',[234 662 50 22],'FontSize',9, ...
                'ValueChangedFcn', createCallbackFcn(app,@SuresiEditFieldValueChanged,true));
            app.SuresiSlider = uislider(SS,'Limits',[0.5 30],'Value',3, ...
                'Position',[5 656 275 3], ...
                'ValueChangedFcn', createCallbackFcn(app,@SuresiSliderValueChanged,true));

            uilabel(SS,'Text','Fs (Hz):','Position',[5 630 80 18],'FontSize',9);
            app.OrnFsEditField = uieditfield(SS,'numeric','Value',2000,'Limits',[500 20000], ...
                'Position',[90 630 194 22],'FontSize',9);

            uilabel(SS,'Text','Gürültü (%):','Position',[5 602 90 18],'FontSize',9);
            app.GurultuEditField = uieditfield(SS,'numeric','Value',30,'Limits',[0 200], ...
                'Position',[234 602 50 22],'FontSize',9, ...
                'ValueChangedFcn', createCallbackFcn(app,@GurultuEditFieldValueChanged,true));
            app.GurultuSlider = uislider(SS,'Limits',[0 200],'Value',30, ...
                'Position',[5 596 275 3], ...
                'ValueChangedFcn', createCallbackFcn(app,@GurultuSliderValueChanged,true));

            uipanel(SS,'BorderType','line','BackgroundColor',[0.72 0.74 0.82], ...
                'Position',[0 582 290 1]);

            uilabel(SS,'Text','GÜRÜLTÜ BİLEŞENLERİ','Position',[5 564 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            app.Seb50HzCheck = uicheckbox(SS, ...
                'Text','50 Hz Şebeke Gürültüsü  (+ 100 Hz, 150 Hz harmonikler)', ...
                'Value',true,'Position',[5 540 280 22],'FontSize',9);
            app.BaselineCheck = uicheckbox(SS, ...
                'Text','Baseline Wander  (0.3 – 1.5 Hz yavaş kayma)', ...
                'Value',true,'Position',[5 514 280 22],'FontSize',9);

            app.SentetikOlusturButton = uibutton(SS,'push', ...
                'Text','  Sentetik EMG Oluştur', ...
                'Position',[5 474 280 36], ...
                'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.15 0.35 0.82],'FontColor','white', ...
                'ButtonPushedFcn', createCallbackFcn(app,@SentetikOlusturButtonPushed,true));

            uipanel(SS,'BorderType','line','BackgroundColor',[0.72 0.74 0.82], ...
                'Position',[0 464 290 1]);

            uilabel(SS,'Text','FİLTRE UYGULA','Position',[5 446 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            app.SenFiltreTipiDD = uidropdown(SS, ...
                'Items',{'Butterworth (Bandpass)','Notch (50 Hz)', ...
                         'Wavelet (db4)','Tam Zincir (BP + Notch)'}, ...
                'Position',[5 420 280 26],'FontSize',9);

            app.SenFiltreUygButton = uibutton(SS,'push', ...
                'Text','  Filtreyi Uygula', ...
                'Position',[5 382 280 34], ...
                'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.06 0.55 0.16],'FontColor','white', ...
                'ButtonPushedFcn', createCallbackFcn(app,@SenFiltreUygButtonPushed,true));

            uipanel(SS,'BorderType','line','BackgroundColor',[0.72 0.74 0.82], ...
                'Position',[0 372 290 1]);

            uilabel(SS,'Text','METRİKLER  (filtrelenmiş sinyal)','Position',[5 354 280 18], ...
                'FontWeight','bold','FontSize',10,'FontColor',[0.15 0.20 0.52]);

            senP = uipanel(SS,'BorderType','line','Position',[3 5 284 346]);

            sen_lbl  = {'SNR (ref. göre dB):', 'RMS:', 'Median Frekans:'};
            sen_prop = {'SenSNRDegLabel','SenRMSDegLabel','SenMFDegLabel'};
            sen_tip  = {'Gürültüsüz referans sinyal üzerinden SNR', ...
                        'Filtrelenmiş sinyalin kök ortalama kare değeri', ...
                        'Filtrelenmiş sinyalin medyan frekansı'};
            for mi = 1:3
                ry = 318 - (mi-1)*50;
                uilabel(senP,'Text',sen_lbl{mi},'Position',[6 ry 158 18], ...
                    'FontSize',9,'FontWeight','bold','Tooltip',sen_tip{mi});
                app.(sen_prop{mi}) = uilabel(senP,'Text','—', ...
                    'Position',[168 ry 110 18],'FontSize',12, ...
                    'FontColor',[0.72 0.18 0.04],'FontWeight','bold');
            end
            uilabel(senP,'Text', ...
                sprintf(['Not: SNR, üretilen temiz (gürültüsüz)\n' ...
                         'referans sinyal üzerinden hesaplanır.\n' ...
                         'Bu değer gerçek SNR''ye çok yakındır.']), ...
                'Position',[6 8 270 55],'FontSize',8,'FontColor',[0.50 0.50 0.55], ...
                'WordWrap','on');

            % ---------- Sağ grafik alanı ----------
            SR = uipanel(app.SentetikTab,'BorderType','none','Position',[302 5 976 714]);

            app.SenHamAxes = uiaxes(SR,'Position',[5 488 960 218]);
            title(app.SenHamAxes,'Sentetik Ham EMG  —  Gürültülü & Temiz Referans');
            xlabel(app.SenHamAxes,'Zaman (s)'); ylabel(app.SenHamAxes,'Genlik');
            grid(app.SenHamAxes,'on');

            app.SenFiltAxes = uiaxes(SR,'Position',[5 265 960 218]);
            title(app.SenFiltAxes,'Filtrelenmiş Sinyal  —  Temiz Referansla Karşılaştırma');
            xlabel(app.SenFiltAxes,'Zaman (s)'); ylabel(app.SenFiltAxes,'Genlik');
            grid(app.SenFiltAxes,'on');

            app.SenPSDAxes = uiaxes(SR,'Position',[5 5 960 252]);
            title(app.SenPSDAxes,'Güç Spektral Yoğunluğu  —  Welch Yöntemi');
            xlabel(app.SenPSDAxes,'Frekans (Hz)'); ylabel(app.SenPSDAxes,'Güç Yoğunluğu');
            grid(app.SenPSDAxes,'on');

            % Göster
            app.UIFigure.Visible = 'on';

        end % createComponents

    end % component methods

    % =====================================================================
    %  BAŞLATMA & KAPATMA
    % =====================================================================
    methods (Access = public)

        function app = DelsysNoiseMaster
            createComponents(app);
            registerApp(app, app.UIFigure);
            guncelleFiltreGorunu(app);

            if nargout == 0
                clear app;
            end
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

    end

end % classdef


% =========================================================================
%  YEREL YARDIMCI FONKSİYON
% =========================================================================
function mf = medianFreqLocal(signal, fs)
    n   = length(signal);
    win = min(round(n/4), 1024);
    [pxx, f] = pwelch(signal, win, [], [], fs);
    cum = cumsum(pxx);
    idx = find(cum >= cum(end)/2, 1, 'first');
    if isempty(idx)
        mf = 0;
    else
        mf = f(idx);
    end
end
