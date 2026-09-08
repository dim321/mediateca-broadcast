import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "filter", "selectAll", "count", "groupSelect"]

  connect() {
    this.filterRows()
    this.syncCount()
    this.syncGroupOptions()
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
    this.syncGroupOptions()
  }

  selectionChanged() {
    this.syncCount()
    this.syncSelectAll()
    this.syncGroupOptions()
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

  syncGroupOptions() {
    const selectedIds = new Set()
    this.rowTargets.forEach((row) => {
      if (!this.rowCheckbox(row)?.checked) return

      ;(row.dataset.groupIds || "").split(",").filter(Boolean).forEach((id) => selectedIds.add(id))
    })

    this.groupSelectTargets.forEach((select) => {
      Array.from(select.options).forEach((option) => {
        if (!option.value) {
          option.hidden = false
          return
        }

        option.hidden = selectedIds.size > 0 && !selectedIds.has(option.value)
      })

      if (select.value && select.selectedOptions[0]?.hidden) select.value = ""
    })
  }
}
