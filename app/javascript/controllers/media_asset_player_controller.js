import { Controller } from "@hotwired/stimulus"
import mpegts from "mpegts.js"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue || !mpegts.isSupported()) return

    this.player = mpegts.createPlayer({
      type: "mse",
      isLive: false,
      url: this.urlValue
    })
    this.player.attachMediaElement(this.element)
    this.player.load()
  }

  disconnect() {
    if (!this.player) return

    this.player.destroy()
    this.player = null
  }
}
