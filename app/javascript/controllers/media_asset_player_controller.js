import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  async connect() {
    this.disconnected = false
    if (!this.urlValue) return

    const { default: mpegts } = await import("mpegts.js")
    if (this.disconnected || !mpegts.isSupported()) return

    this.player = mpegts.createPlayer({
      type: "mse",
      isLive: false,
      url: this.urlValue
    })
    this.player.attachMediaElement(this.element)
    this.player.load()
  }

  disconnect() {
    this.disconnected = true
    if (!this.player) return

    this.player.destroy()
    this.player = null
  }
}
