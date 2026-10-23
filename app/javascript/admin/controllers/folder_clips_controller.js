import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "row" ]
  static values = { emptyMessage: String }

  connect() {
    this.beforeStream = (event) => this.animateRemoval(event)
    document.addEventListener("turbo:before-stream-render", this.beforeStream)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.beforeStream)
  }

  rowTargetConnected(row) {
    if (row.dataset.animate !== "enter") return

    this.play(row, "folder-clip-row--enter", () => {
      row.classList.remove("folder-clip-row--enter")
      delete row.dataset.animate
    })
  }

  animateRemoval(event) {
    const stream = event.target
    if (stream.action !== "remove") return

    const row = this.element.querySelector(`#${CSS.escape(stream.target)}`)
    if (!row || !this.rowTargets.includes(row)) return

    const render = event.detail.render
    event.detail.render = async (streamElement) => {
      await this.play(row, "folder-clip-row--leave")
      await render(streamElement)
      if (row.isConnected) row.remove()
      this.showEmptyIfNeeded()
    }
  }

  showEmptyIfNeeded() {
    if (this.rowTargets.length > 0) return

    const message = document.createElement("p")
    message.className = "text-sm text-gray-500"
    message.textContent = this.emptyMessageValue
    this.element.replaceChildren(message)
  }

  play(row, className, done = () => {}) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      done()
      return Promise.resolve()
    }

    return new Promise((resolve) => {
      let finished = false
      const finish = () => {
        if (finished) return

        finished = true
        done()
        resolve()
      }

      row.classList.add(className)
      row.addEventListener("animationend", finish, { once: true })
      window.setTimeout(finish, 400)
    })
  }
}
