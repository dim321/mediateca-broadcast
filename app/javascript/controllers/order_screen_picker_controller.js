import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "filter", "selectAll", "count", "rowTemplate", "gridLines", "gridRow", "showsPerHour"]

  connect() {
    this.filterRows()
    this.syncCount()
    this.syncGridRows()
    this.syncFrequencyOptions()
  }

  filterRows() {
    const filters = this.filterEntries()
    this.rowTargets.forEach((row) => {
      row.hidden = !filters.every(([key, value]) => {
        if (!value) return true
        return (row.dataset[key] || "").toLowerCase().includes(value)
      })
    })
    this.syncSelectAll()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.visibleRows().forEach((row) => {
      const box = this.rowCheckbox(row)
      if (box) box.checked = checked
    })
    this.syncCount()
    this.syncGridRows()
    this.syncFrequencyOptions()
  }

  selectionChanged() {
    this.syncCount()
    this.syncSelectAll()
    this.syncGridRows()
    this.syncFrequencyOptions()
  }

  filterEntries() {
    return this.filterTargets.map((input) => [input.dataset.filterKey, input.value.trim().toLowerCase()])
  }

  visibleRows() {
    return this.rowTargets.filter((row) => !row.hidden)
  }

  rowCheckbox(row) {
    return row.querySelector('input[type="checkbox"]')
  }

  syncSelectAll() {
    if (!this.hasSelectAllTarget) return

    const boxes = this.visibleRows().map((row) => this.rowCheckbox(row)).filter(Boolean)
    const selected = boxes.filter((box) => box.checked)
    this.selectAllTarget.checked = boxes.length > 0 && selected.length === boxes.length
    this.selectAllTarget.indeterminate = selected.length > 0 && selected.length < boxes.length
  }

  syncCount() {
    if (!this.hasCountTarget) return

    const selected = this.rowTargets.filter((row) => this.rowCheckbox(row)?.checked).length
    this.countTarget.textContent = String(selected)
  }

  syncGridRows() {
    if (!this.hasGridLinesTarget || !this.hasRowTemplateTarget) return

    const selectedRows = this.rowTargets.filter((row) => this.rowCheckbox(row)?.checked)
    const selectedIds = new Set(selectedRows.map((row) => this.rowCheckbox(row).value))

    this.gridRowTargets.forEach((row) => {
      if (!selectedIds.has(String(row.dataset.screenId))) row.remove()
    })

    selectedRows.forEach((pickerRow) => {
      const id = this.rowCheckbox(pickerRow).value
      if (this.gridRowTargets.some((row) => String(row.dataset.screenId) === id)) return
      this.appendGridRow(pickerRow, id)
    })

    this.dispatch("recompute", { prefix: "order-grid" })
    const grid = this.element
    grid.dispatchEvent(new Event("input", { bubbles: true }))
  }

  appendGridRow(pickerRow, screenId) {
    const html = this.rowTemplateTarget.innerHTML
      .replaceAll("NEW_LINE", `screen-${screenId}`)
      .replaceAll("NEW_SCREEN", screenId)
    this.gridLinesTarget.insertAdjacentHTML("beforeend", html)
    const row = this.gridLinesTarget.lastElementChild
    if (!row) return

    row.dataset.screenId = screenId
    row.dataset.hours = pickerRow.dataset.hours || "{}"
    const idInput = row.querySelector("[data-order-screen-picker-target='screenId']")
    if (idInput) idInput.value = screenId
    const name = row.querySelector("[data-order-screen-picker-target='screenName']")
    if (name) name.textContent = pickerRow.dataset.screenName || ""
    const meta = row.querySelector("[data-order-screen-picker-target='screenMeta']")
    if (meta) meta.textContent = pickerRow.dataset.screenMeta || ""
  }

  syncFrequencyOptions() {
    if (!this.hasShowsPerHourTarget) return

    const selected = this.rowTargets.filter((row) => this.rowCheckbox(row)?.checked)
    const select = this.showsPerHourTarget
    const previous = select.value

    let options = []
    if (selected.length > 0) {
      const sets = selected.map((row) => {
        try {
          return JSON.parse(row.dataset.frequencies || "[]")
        } catch (_error) {
          return []
        }
      })
      options = sets.reduce((acc, set) => acc.filter((item) => set.includes(item)))
      options.sort((a, b) => a - b)
    }

    select.innerHTML = ""
    const blank = document.createElement("option")
    blank.value = ""
    select.append(blank)
    options.forEach((value) => {
      const option = document.createElement("option")
      option.value = String(value)
      option.textContent = String(value)
      select.append(option)
    })

    const keep = options.map(String).includes(previous) ? previous : ""
    select.value = keep
    select.disabled = options.length === 0
    this.dispatch("recompute", { prefix: "order-grid" })
  }
}
