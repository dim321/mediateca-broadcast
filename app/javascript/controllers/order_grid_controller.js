import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "skipped", "showsPerHour", "distributionStrategy", "windowStart", "windowEnd", "lineRow", "lines", "total", "grandTotal"]

  connect() {
    this.recompute()
  }

  recompute() {
    const rate = Number.parseInt(this.hasShowsPerHourTarget ? this.showsPerHourTarget.value : "", 10) || 0
    const windows = this.currentWindows()

    this.lineRowTargets.forEach((row) => {
      let hours = {}
      try {
        hours = JSON.parse(row.dataset.hours || "{}")
      } catch (_error) {
        hours = {}
      }

      row.querySelectorAll('[data-order-grid-target="cell"]').forEach((cell) => {
        if (this.cellSkipped(cell)) {
          this.updateCellAppearance(cell)
          return
        }

        const openHours = hours[cell.dataset.date] || []
        const baseShows = rate * this.coveredHourCount(openHours, windows)
        const { screenIndex, screenCount } = this.screenPosition(row)
        cell.value = String(this.distributedShows(
          baseShows,
          cell.dataset.date,
          screenIndex,
          screenCount
        ))
        this.updateCellAppearance(cell)
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
    this.updateCellAppearance(cell)
    const row = cell.closest('[data-order-grid-target="lineRow"]')
    if (row) this.updateRowTotal(row)
    this.updateGrandTotal()
  }

  cellSkipped(cell) {
    if (cell.dataset.skipped === "1") return true

    const skipped = cell.parentElement?.querySelector('[data-order-grid-target="skipped"]')
    return skipped?.value === "1"
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

  currentWindows() {
    return Array.from(this.element.querySelectorAll("[data-order-windows-target='row']")).flatMap((row) => {
      const start = this.parseClock(row.querySelector("[data-order-grid-target='windowStart']")?.value)
      const end = this.parseClock(row.querySelector("[data-order-grid-target='windowEnd']")?.value)
      if (start == null || end == null || start >= end) return []

      return [[start, end]]
    })
  }

  parseClock(value) {
    const match = String(value || "").trim().match(/^(\d{1,2}):(\d{2})/)
    if (!match) return null

    const hours = Number.parseInt(match[1], 10)
    const minutes = Number.parseInt(match[2], 10)
    if (hours > 23 || minutes > 59) return null

    return hours * 60 + minutes
  }

  coveredHourCount(openHours, windows) {
    const hours = Array.isArray(openHours) ? openHours : []
    return hours.filter((hour) => {
      const hourStart = Number(hour) * 60
      const hourEnd = hourStart + 60
      return windows.some(([start, end]) => start < hourEnd && end > hourStart)
    }).length
  }

  updateCellAppearance(cell) {
    const hasShows = (Number.parseInt(cell.value, 10) || 0) > 0
    cell.classList.toggle("bg-success/15", hasShows)
    cell.classList.toggle("border-success/40", hasShows)
    cell.classList.toggle("bg-base-200", !hasShows)
    cell.classList.toggle("border-base-300", !hasShows)
  }

  distributedShows(baseShows, dateValue, screenIndex, screenCount) {
    const strategy = this.hasDistributionStrategyTarget
      ? this.distributionStrategyTargets.find((target) => target.checked)?.value || "linear"
      : "linear"
    const date = this.parseDate(dateValue)

    if (!date) return baseShows
    if (strategy === "weekdays" && this.weekend(date)) return 0
    if (strategy === "weekends" && !this.weekend(date)) return 0
    if (strategy === "even_days" && date.getUTCDate() % 2 !== 0) return 0
    if (strategy === "odd_days" && date.getUTCDate() % 2 === 0) return 0
    if (strategy !== "chess") return baseShows

    const firstHalfDay = date.getUTCDate() % 2 !== 0
    const firstHalfSize = Math.ceil(screenCount / 2)
    const inFirstHalf = screenIndex < firstHalfSize

    return firstHalfDay === inFirstHalf ? baseShows : 0
  }

  screenPosition(row) {
    const rows = Array.from(
      row.closest("table")?.querySelectorAll('[data-order-grid-target="lineRow"]') || []
    )

    return {
      screenIndex: rows.indexOf(row),
      screenCount: rows.length
    }
  }

  parseDate(value) {
    if (!value) return null

    const [year, month, day] = value.split("-").map(Number)
    return new Date(Date.UTC(year, month - 1, day))
  }

  weekend(date) {
    return date.getUTCDay() === 0 || date.getUTCDay() === 6
  }
}
