import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "skipped", "showsPerHour", "windowStart", "windowEnd", "lineRow", "lines"]

  connect() {
    this.recompute()
  }

  recompute() {
    const rate = Number.parseInt(this.hasShowsPerHourTarget ? this.showsPerHourTarget.value : "", 10) || 0

    this.lineRowTargets.forEach((row) => {
      let hours = {}
      try {
        hours = JSON.parse(row.dataset.hours || "{}")
      } catch (_error) {
        hours = {}
      }

      row.querySelectorAll('[data-order-grid-target="cell"]').forEach((cell) => {
        if (cell.dataset.skipped === "1" || cell.value === "0") return

        const count = hours[cell.dataset.date] || 0
        cell.value = rate * count
      })
    })
  }

  cellChanged(event) {
    const cell = event.target
    const skipped = cell.closest("div")?.querySelector('[data-order-grid-target="skipped"]')
    if (cell.value === "0") {
      cell.dataset.skipped = "1"
      if (skipped) skipped.value = "1"
    } else {
      cell.dataset.skipped = ""
      if (skipped) skipped.value = "0"
    }
  }
}
