// Живые обновления статус-страницы через Server-Sent Events.
// Никаких фреймворков: Play отдаёт готовый HTML, JS только подкрашивает изменения.
(function () {
    var container = document.getElementById('live');
    if (!container || !window.EventSource) {
        return;
    }

    var org = container.getAttribute('data-org');
    var source = new EventSource('/s/' + encodeURIComponent(org) + '/live');

    function setStatus(text) {
        container.textContent = text;
    }

    source.addEventListener('open', function () {
        setStatus('live');
    });

    source.addEventListener('probe', function (message) {
        var event = JSON.parse(message.data);
        var row = document.querySelector('tr[data-service="' + event.serviceKey + '"]');
        if (!row) {
            return;
        }
        var state = row.querySelector('.state');
        var p95 = row.querySelector('.p95');
        if (state) {
            state.textContent = event.outcome;
            state.className = 'state ' + event.outcome.toLowerCase();
        }
        if (p95 && typeof event.durationMs === 'number') {
            p95.textContent = event.durationMs + ' ms';
        }
        setStatus('last update: ' + new Date().toLocaleTimeString());
    });

    source.addEventListener('incident_opened', function (message) {
        var event = JSON.parse(message.data);
        setStatus('incident opened: ' + event.title);
    });

    source.addEventListener('incident_resolved', function () {
        setStatus('incident resolved');
    });

    source.addEventListener('error', function () {
        // Браузер переподключится сам: серверу достаточно держать поток живым.
        setStatus('reconnecting...');
    });
})();
