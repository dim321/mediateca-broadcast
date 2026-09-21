import { Controller } from "@hotwired/stimulus"

const SELECTED_CELL_CLASSES = ["ring-2", "ring-primary", "ring-inset"]
const ZERO_SELECTION_KEYS = new Set(["0", "x", "X", " ", "Space", "Spacebar"])

export default class extends Controller {
  static targets = ["cell", "skipped", "showsPerHour", "distributionStrategy", "windowStart", "windowEnd", "lineRow", "lines", "total", "grandTotal", "marquee"]
  static values = { selectionThreshold: { type: Number, default: 4 } }

  initialize() {
    this.selectedCells = new Set()
    this.selectionSnapshot = new Set()
  }

  connect() {
    this.recompute()
  }

  disconnect() {
    this.clearClickGuard()
    this.stopSelecting()
    this.clearSelection()
  }

  cellTargetDisconnected(cell) {
    this.selectedCells.delete(cell)
    this.selectionSnapshot.delete(cell)
  }

  startSelection(event) {
    if (!this.isPrimaryMouse(event)) return

    const cell = this.cellFromEvent(event)
    if (!cell) {
      if (!event.shiftKey) this.clearSelection()
      return
    }

    this.stopSelecting()
    this.selecting = true
    this.pointerId = event.pointerId
    this.selectionOrigin = { x: event.clientX, y: event.clientY }
    this.selectionAdditive = event.shiftKey
    this.selectionSnapshot = this.selectionAdditive ? new Set(this.selectedCells) : new Set()
    this.selectionDragged = false
    this.selectionAnchor = cell
    this.lastSelectionPoint = { x: event.clientX, y: event.clientY }
    cell.focus({ preventScroll: true })
  }

  moveSelection(event) {
    if (!this.selecting || event.pointerId !== this.pointerId) return

    this.lastSelectionPoint = { x: event.clientX, y: event.clientY }
    if (this.selectionFrame) return

    this.selectionFrame = requestAnimationFrame(() => this.flushSelectionMove())
  }

  endSelection(event) {
    if (!this.selecting || event.pointerId !== this.pointerId) return

    this.flushSelectionMove()
    if (!this.selectionDragged && this.selectionAnchor) {
      if (this.selectionAdditive) this.toggleSelected(this.selectionAnchor)
      else this.replaceSelection([ this.selectionAnchor ])
    }
    if (this.selectionDragged) this.suppressClickAfterDrag()
    this.stopSelecting()
  }

  cancelSelection(event) {
    if (!this.selecting) return
    if (event && event.pointerId !== this.pointerId) return

    this.replaceSelection([ ...this.selectionSnapshot ])
    this.stopSelecting()
  }

  selectionKeydown(event) {
    if (event.defaultPrevented || event.repeat) return
    if (event.altKey || event.ctrlKey || event.metaKey) return
    if (!this.isZeroSelectionKey(event)) return
    if (this.selectedCells.size === 0) return
    if (this.isTypingField(event.target)) return

    event.preventDefault()
    this.zeroSelectedCells()
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

  flushSelectionMove() {
    if (this.selectionFrame) {
      cancelAnimationFrame(this.selectionFrame)
      this.selectionFrame = null
    }
    if (!this.selecting || !this.lastSelectionPoint || !this.selectionOrigin) return

    const { x, y } = this.lastSelectionPoint
    if (!this.selectionDragged) {
      const dx = x - this.selectionOrigin.x
      const dy = y - this.selectionOrigin.y
      if ((dx * dx) + (dy * dy) < this.selectionThresholdValue ** 2) return

      this.selectionDragged = true
      document.documentElement.classList.add("select-none")
      window.getSelection()?.removeAllRanges()
    }

    this.updateMarquee(x, y)
    this.applyRectSelection(x, y)
  }

  applyRectSelection(x, y) {
    const cells = this.cellsInRect(this.selectionRect(x, y))
    if (this.selectionAdditive) {
      this.replaceSelection([ ...this.selectionSnapshot, ...cells ])
    } else {
      this.replaceSelection(cells)
    }
  }

  toggleSelected(cell) {
    const next = new Set(this.selectedCells)
    if (next.has(cell)) next.delete(cell)
    else next.add(cell)
    this.replaceSelection([ ...next ])
  }

  replaceSelection(cells) {
    const next = new Set(cells.filter((cell) => this.cellTargets.includes(cell)))

    this.selectedCells.forEach((cell) => {
      if (!next.has(cell)) this.setCellSelected(cell, false)
    })
    next.forEach((cell) => {
      if (!this.selectedCells.has(cell)) this.setCellSelected(cell, true)
    })
    this.selectedCells = next
  }

  clearSelection() {
    this.replaceSelection([])
  }

  setCellSelected(cell, selected) {
    const container = cell.closest("td") || cell
    SELECTED_CELL_CLASSES.forEach((name) => container.classList.toggle(name, selected))
    if (selected) cell.setAttribute("aria-selected", "true")
    else cell.removeAttribute("aria-selected")
  }

  zeroSelectedCells() {
    this.selectedCells.forEach((cell) => {
      cell.value = "0"
      this.cellChanged({ target: cell })
    })
  }

  cellsInRect(rect) {
    return this.cellTargets.filter((cell) => {
      if (cell.disabled) return false

      const box = cell.getBoundingClientRect()
      return box.width > 0 && box.height > 0 && this.rectsIntersect(rect, box)
    })
  }

  selectionRect(x, y) {
    return {
      left: Math.min(this.selectionOrigin.x, x),
      top: Math.min(this.selectionOrigin.y, y),
      right: Math.max(this.selectionOrigin.x, x),
      bottom: Math.max(this.selectionOrigin.y, y)
    }
  }

  rectsIntersect(a, b) {
    return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top
  }

  updateMarquee(x, y) {
    if (!this.hasMarqueeTarget || !this.selectionOrigin) return

    const rect = this.selectionRect(x, y)
    this.marqueeTarget.style.left = `${rect.left}px`
    this.marqueeTarget.style.top = `${rect.top}px`
    this.marqueeTarget.style.width = `${Math.max(1, rect.right - rect.left)}px`
    this.marqueeTarget.style.height = `${Math.max(1, rect.bottom - rect.top)}px`
    this.marqueeTarget.classList.remove("hidden")
  }

  hideMarquee() {
    if (!this.hasMarqueeTarget) return

    this.marqueeTarget.classList.add("hidden")
    this.marqueeTarget.style.width = "0px"
    this.marqueeTarget.style.height = "0px"
  }

  stopSelecting() {
    if (this.selectionFrame) {
      cancelAnimationFrame(this.selectionFrame)
      this.selectionFrame = null
    }
    document.documentElement.classList.remove("select-none")
    this.hideMarquee()
    this.selecting = false
    this.selectionDragged = false
    this.pointerId = null
    this.selectionOrigin = null
    this.selectionAnchor = null
    this.lastSelectionPoint = null
    this.selectionSnapshot = new Set()
  }

  suppressClickAfterDrag() {
    if (this.clickGuard) return

    this.clickGuard = (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.clearClickGuard()
    }
    document.addEventListener("click", this.clickGuard, { capture: true })
  }

  clearClickGuard() {
    if (!this.clickGuard) return

    document.removeEventListener("click", this.clickGuard, { capture: true })
    this.clickGuard = null
  }

  cellFromEvent(event) {
    const node = event.target
    if (!(node instanceof Element)) return null

    const cell = node.closest('[data-order-grid-target="cell"]')
      || node.closest("td")?.querySelector('[data-order-grid-target="cell"]')
    if (!cell || !this.cellTargets.includes(cell)) return null

    return cell
  }

  isPrimaryMouse(event) {
    return event.pointerType === "mouse" && event.button === 0 && event.isPrimary !== false
  }

  isZeroSelectionKey(event) {
    return ZERO_SELECTION_KEYS.has(event.key) || event.code === "Space" || event.code === "Digit0" || event.code === "KeyX"
  }

  isTypingField(node) {
    if (!(node instanceof HTMLElement)) return false
    if (this.cellTargets.includes(node)) return false
    if (node.isContentEditable) return true
    if (node.tagName === "TEXTAREA") return true
    if (node.tagName !== "INPUT") return false

    const type = (node.type || "text").toLowerCase()
    return [ "text", "search", "email", "password", "tel", "url", "date", "datetime-local", "time" ].includes(type)
  }
}
