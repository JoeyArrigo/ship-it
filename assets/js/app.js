// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Celebration animations hook
let Hooks = {}
Hooks.CelebrationAnimations = {
  mounted() {
    this.handleEvent("celebrate-raise", () => this.triggerCelebration("raise"))
    this.handleEvent("celebrate-win", () => this.triggerCelebration("win"))
  },

  triggerCelebration(type) {
    const container = this.el
    const symbols = ["♣", "♦", "♥", "♠"]
    const colors = ["neo-club", "neo-diamond", "neo-heart", "neo-spade"]

    // Clear any existing confetti
    container.innerHTML = ""

    // Number of confetti pieces
    const count = type === "win" ? 50 : 25

    for (let i = 0; i < count; i++) {
      setTimeout(() => {
        const confetti = document.createElement("div")
        const symbolIndex = Math.floor(Math.random() * symbols.length)

        confetti.textContent = symbols[symbolIndex]
        confetti.className = `confetti-symbol ${colors[symbolIndex]}`

        // Random horizontal position
        confetti.style.left = Math.random() * 100 + "%"

        // Random animation delay for staggered effect
        confetti.style.animationDelay = (Math.random() * 0.5) + "s"

        container.appendChild(confetti)
        container.classList.add(`celebration-${type}`)

        // Remove confetti after animation
        setTimeout(() => {
          if (confetti.parentNode) {
            confetti.parentNode.removeChild(confetti)
          }
        }, type === "win" ? 4000 : 2000)
      }, i * 50) // Stagger creation by 50ms
    }

    // Remove celebration class after animation completes
    setTimeout(() => {
      container.classList.remove(`celebration-${type}`)
    }, type === "win" ? 4000 : 2000)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket