// Клиентская часть дашборда: LiveView-сокет и не более того.
// Вся логика живёт на сервере; сюда попадает только то, что без браузера не работает.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()

// Доступно в консоли браузера: liveSocket.enableDebug(), liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket
