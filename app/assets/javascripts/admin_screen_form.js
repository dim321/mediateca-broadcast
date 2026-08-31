(function () {
  function formFrom(element) {
    return element.closest("form");
  }

  function locationSelect(form) {
    return form.querySelector("[data-screen-location-select]");
  }

  function stationSelect(form) {
    return form.querySelector("[data-screen-station-select]");
  }

  function nameInput(form) {
    return form.querySelector("#screen_name");
  }

  function suggestedName(form) {
    var select = stationSelect(form);
    if (!select) return "";

    var option = select.options[select.selectedIndex];
    if (!option || !option.value) return "";

    return option.dataset.suggestedName || "";
  }

  function autoFillEnabled(form) {
    var select = locationSelect(form);
    return select && select.dataset.autoFillName === "true";
  }

  function filterStations(form) {
    var location = locationSelect(form);
    var station = stationSelect(form);
    if (!location || !station) return;

    var locationId = location.value;
    Array.from(station.options).forEach(function (option) {
      if (!option.value) {
        option.hidden = false;
        return;
      }

      var match = option.dataset.locationId === locationId;
      option.hidden = !match;
      if (!match && option.selected) option.selected = false;
    });
  }

  function fillName(form) {
    if (!autoFillEnabled(form)) return;

    var input = nameInput(form);
    if (!input) return;

    var suggested = suggestedName(form);
    var last = form.dataset.lastSuggestedName || "";
    if (input.value && input.value !== last) return;

    input.value = suggested;
    form.dataset.lastSuggestedName = suggested;
  }

  function initForm(form) {
    filterStations(form);
  }

  function initAll() {
    document.querySelectorAll("[data-screen-location-select]").forEach(function (select) {
      var form = formFrom(select);
      if (form) initForm(form);
    });
  }

  document.addEventListener("change", function (event) {
    var target = event.target;
    if (!(target instanceof Element)) return;

    var form = formFrom(target);
    if (!form) return;

    if (target.matches("[data-screen-location-select]")) {
      filterStations(form);
      fillName(form);
    }

    if (target.matches("[data-screen-station-select]")) {
      fillName(form);
    }
  });

  document.addEventListener("turbo:load", initAll);
  document.addEventListener("DOMContentLoaded", initAll);
})();
