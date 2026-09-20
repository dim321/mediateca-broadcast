import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import OrderGridController from "controllers/order_grid_controller"
import OrderGridDateController from "controllers/order_grid_date_controller"
import OrderMediaAssetsController from "controllers/order_media_assets_controller"
import OrderScreenPickerController from "controllers/order_screen_picker_controller"
import OrderWindowsController from "controllers/order_windows_controller"

const application = Application.start()
application.debug = false
window.Stimulus = application

eagerLoadControllersFrom("admin/controllers", application)
application.register("order-grid", OrderGridController)
application.register("order-grid-date", OrderGridDateController)
application.register("order-media-assets", OrderMediaAssetsController)
application.register("order-screen-picker", OrderScreenPickerController)
application.register("order-windows", OrderWindowsController)
