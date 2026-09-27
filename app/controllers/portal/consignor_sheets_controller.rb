module Portal
  # « Imprimer ma feuille » (epic #359, phase 3) : la feuille du carnet
  # Artisanat de l'artisan connecté, et de lui seul — rien dans l'URL.
  class ConsignorSheetsController < Portal::BaseController
    layout "print_sheet"

    before_action :require_portal_consignor

    def show
      @consignor = current_portal_consignor
      @qr = Shop::EpcQrCode.new(communication: @consignor.sheet_communication)
      @printed_on = Date.current
      @number = @consignor.next_sheet_number! if @qr.configured?
      render "shop/sheets/consignor"
    end
  end
end
