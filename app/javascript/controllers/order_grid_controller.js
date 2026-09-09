import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "skipped", "showsPerHour", "windowStart", "windowEnd", "lineRow", "lines", "total", "grandTotal"]

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
      this.updateRowTotal(row)
    })
    this.updateGrandTotal()
  }

  cellChanged(event) {
    const cell = event.target
        const skipped = cell.parentElement?.querySelector('[data-order-grid-target="skipped"]')
    if (cell.value === "0") {
      cell.dataset.skipped = "1"
      if (skipped) skipped.value = "1"
    } else {
      cell.dataset.skipped = ""
      if (skipped) skipped.value = "0"
    }
    const row = cell.closest('[data-order-grid-target="lineRow"]')
    if (row) this.updateRowTotal(row)
    this.updateGrandTotal()
  }

  updateRowTotal(row) {
    const total = row.querySelector('[data-order-grid-target="total"]')
    if (!total) return

    const sum = Array.from(row.querySelectorAll('[data-order-grid-target="cell"]'))
      .reduce((acc, cell) => acc + (Number.parseInt(cell.value, 10) || 0), 0)
    total.value = String(sum)
  }

  updateGrandTotal() {
    if (!this.hasGrandTotalTarget) return

    const sum = this.lineRowTargets.reduce((acc, row) => {
      const total = row.querySelector('[data-order-grid-target="total"]')
      return acc + (Number.parseInt(total?.value, 10) || 0)
    }, 0)
    this.grandTotalTarget.value = String(sum)
  }
}
