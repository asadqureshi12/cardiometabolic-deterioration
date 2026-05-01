var patientsData = [];
var stringData = [];
var markerData = [];
var monthlyData = [];
var chartInstance = null;

function loadCSV(path) {
    return fetch(path)
        .then(function(response) { return response.text(); })
        .then(function(text) {
            return Papa.parse(text, { header: true, skipEmptyLines: true }).data;
        });
}

function init() {
    Promise.all([
        loadCSV('data/patients_grid.csv'),
        loadCSV('data/scoring_string_export.csv'),
        loadCSV('data/marker_data_quality_export.csv'),
        loadCSV('data/monthly_scores_export.csv')
    ]).then(function(results) {
        patientsData = results[0];
        stringData = results[1];
        markerData = results[2];
        monthlyData = results[3];

        document.getElementById('cohort-summary').textContent =
            patientsData.length + ' patients loaded';

        setupSearch();
    }).catch(function(e) {
        document.getElementById('cohort-summary').textContent =
            'Error loading data: ' + e.message;
    });
}

function setupSearch() {
    var input = document.getElementById('patient-search');
    var suggestions = document.getElementById('suggestions');

    input.addEventListener('input', function () {
        var query = this.value.trim().toLowerCase();
        suggestions.innerHTML = '';

        if (query.length < 2) {
            suggestions.style.display = 'none';
            return;
        }

        var matches = patientsData
            .filter(function(p) { return p.patient_id.toLowerCase().includes(query); })
            .slice(0, 10);

        if (matches.length === 0) {
            suggestions.style.display = 'none';
            return;
        }

        matches.forEach(function(p) {
            var div = document.createElement('div');
            div.textContent = p.patient_id + '  ·  Band ' + p.final_band + '  ·  ' + p.cvd_status;
            div.addEventListener('click', function () {
                input.value = p.patient_id;
                suggestions.style.display = 'none';
                renderPatient(p.patient_id);
            });
            suggestions.appendChild(div);
        });

        suggestions.style.display = 'block';
    });

    document.addEventListener('click', function (e) {
        if (!e.target.closest('#search-section')) {
            suggestions.style.display = 'none';
        }
    });
}

function suffToTier(suff) {
    if (suff === 'BLUE') return 'DATA SUFFICIENT';
    if (suff === 'YELLOW') return 'PARTIALLY SUFFICIENT';
    if (suff === 'GREY') return 'DATA INSUFFICIENT';
    return suff;
}

function renderPatient(patientId) {
    var patient = patientsData.find(function(p) { return p.patient_id === patientId; });
    var scoring = stringData.find(function(s) { return s.patient_id === patientId; });
    var markers = markerData.filter(function(m) { return m.patient_id === patientId; });
    var monthly = monthlyData.filter(function(m) { return m.patient_id === patientId; });

    if (!patient) return;

    document.getElementById('patient-detail').classList.remove('hidden');

    var existing = document.getElementById('alert-banner');
    if (existing) existing.remove();
    if (patient.system_trajectory === 'WORSENING' && patient.system_variance === 'UNSTABLE') {
        var banner = document.createElement('div');
        banner.id = 'alert-banner';
        banner.innerHTML = 'WORSENING + UNSTABLE — Clinical review recommended';
        document.getElementById('patient-detail').prepend(banner);
    }

    renderSummary(patient);
    renderString(scoring, patient);
    renderMarkers(markers);
    renderChart(monthly);
}

function renderSummary(patient) {
    var grid = document.getElementById('summary-grid');
    var suffClass = 'band-suff-' + patient.data_sufficiency_display;

    var fields = [
        { label: 'Patient ID', value: patient.patient_id },
        { label: 'Final Band', value: '<span class="band-badge ' + suffClass + '">Band ' + patient.final_band + '</span>' },
        { label: 'CVD Status', value: patient.cvd_status },
        { label: 'Trajectory', value: patient.system_trajectory, class: 'traj-' + patient.system_trajectory },
        { label: 'Variance', value: patient.system_variance, class: 'traj-' + patient.system_variance }
    ];

    grid.innerHTML = fields.map(function(f) {
        return '<div class="summary-item">' +
            '<div class="label">' + f.label + '</div>' +
            '<div class="value ' + (f.class || '') + '">' + f.value + '</div>' +
            '</div>';
    }).join('');
}

function renderString(scoring, patient) {
    var display = document.getElementById('string-display');
    var fields = document.getElementById('string-fields');

    if (!scoring) {
        display.textContent = 'No scoring data';
        fields.innerHTML = '';
        return;
    }

    display.innerHTML = '<div class="string-legend">CVD Status | Breaching Markers | Worst Deviation | Condition Count</div>' + (scoring.patient_string || 'No string generated');

    var components = [
        { name: 'CVD Status', value: scoring.cvd_status },
        { name: 'Breach Count', value: scoring.breach_count },
        { name: 'Worst Marker', value: scoring.worst_marker_name || 'None' },
        { name: 'Condition Count', value: scoring.condition_count },
        { name: 'Data Tier', value: suffToTier(patient.data_sufficiency_display) }
    ];

    fields.innerHTML = components.map(function(c) {
        return '<div class="string-field">' +
            '<div class="field-name">' + c.name + '</div>' +
            '<div class="field-value">' + c.value + '</div>' +
            '</div>';
    }).join('');
}

function renderMarkers(markers) {
    var tbody = document.getElementById('marker-tbody');

    if (markers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5">No marker data</td></tr>';
        return;
    }

    tbody.innerHTML = markers.map(function(m) {
        var tierDisplay = m.data_tier.replace(/_/g, ' ');
        var trajClass = m.trajectory ? 'traj-' + m.trajectory : '';
        return '<tr>' +
            '<td>' + m.marker_label + '</td>' +
            '<td>' + (m.mean_i !== '' ? parseFloat(m.mean_i).toFixed(4) : '—') + '</td>' +
            '<td>' + tierDisplay + '</td>' +
            '<td class="' + trajClass + '">' + (m.trajectory || '—') + '</td>' +
            '<td>' + (function() {
                if (m.variance_score === '' || m.variance_score === undefined || m.variance_score === null) return '—';
                var vs = parseFloat(m.variance_score);
                if (isNaN(vs)) return '—';
                return vs > 0.001 ? '<span class="traj-UNSTABLE">UNSTABLE</span>' : '<span class="traj-STABLE">STABLE</span>';
            })() + '</td>' +
            '</tr>';
    }).join('');
}

function renderChart(monthly) {
    var canvas = document.getElementById('monthly-chart');
    var note = document.getElementById('chart-note');

    if (chartInstance) {
        chartInstance.destroy();
        chartInstance = null;
    }

    var allZero = monthly.every(function(m) { return parseFloat(m.mean_i_month) === 0; });

    if (monthly.length === 0 || allZero) {
        note.textContent = monthly.length === 0
            ? 'No monthly data available for this patient'
            : 'All markers within threshold — no exceedance signal';
        note.classList.remove('hidden');
        canvas.style.display = 'none';
        return;
    }

    note.classList.add('hidden');
    canvas.style.display = 'block';

    var markerNames = [];
    monthly.forEach(function(m) {
        if (markerNames.indexOf(m.marker_label) === -1) {
            markerNames.push(m.marker_label);
        }
    });

    var colours = {
        'SBP': '#1A5276',
        'HbA1c': '#2E86C1',
        'LDL': '#48C9B0'
    };

    var datasets = markerNames.map(function(marker) {
        var points = monthly
            .filter(function(m) { return m.marker_label === marker; })
            .sort(function(a, b) { return a.score_date.localeCompare(b.score_date); })
            .map(function(m) {
                return { x: m.score_date, y: parseFloat(m.mean_i_month) };
            });

        return {
            label: marker,
            data: points,
            borderColor: colours[marker] || '#95A5A6',
            backgroundColor: 'transparent',
            borderWidth: 2,
            pointRadius: 4,
            tension: 0.1
        };
    });

    chartInstance = new Chart(canvas, {
        type: 'line',
        data: { datasets: datasets },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            scales: {
                x: {
                    type: 'category',
                    title: { display: true, text: 'Month' }
                },
                y: {
                    title: { display: true, text: 'Mean Exceedance' },
                    beginAtZero: true
                }
            },
            plugins: {
                legend: { position: 'top' }
            }
        }
    });
}

init();