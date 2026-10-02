require "rqrcode"

# Le QR bancaire d'un carnet de l'épicerie (epic #359, phase 3, décision 3) :
# un virement SEPA pré-rempli au format EPC069-12, que l'appli bancaire du
# client lit en un scan. Le montant est laissé VIDE — le client tape son total
# — et la communication porte le mot-clé du carnet (`EPICERIE`, `PAIN`,
# `ARTISANAT EMILIE`) que la banque rapprochera (phase 4).
#
# Toujours vers le compte de la fondation (`ShopSetting`), jamais vers celui
# d'un artisan (décision 16).
#
#   Shop::EpcQrCode.new(communication: "EPICERIE").to_svg
module Shop
  class EpcQrCode
    class NotConfigured < StandardError; end

    # Longueur maximale du texte libre d'un virement SEPA.
    COMMUNICATION_MAX = 140

    attr_reader :communication

    def initialize(communication:, settings: ShopSetting.current)
      @communication = communication.to_s.strip.first(COMMUNICATION_MAX)
      @settings = settings
    end

    def configured? = @settings.bank_configured?

    # Les lignes du standard, dans l'ordre : service tag, version 002, jeu de
    # caractères 1 (UTF-8), identification SCT, BIC (facultatif en 002), nom du
    # bénéficiaire, IBAN, montant (vide), code purpose (vide), référence
    # structurée (vide), communication libre.
    def payload
      raise NotConfigured, "Coordonnées bancaires de l'épicerie non configurées" unless configured?

      [
        "BCD", "002", "1", "SCT",
        @settings.bic.to_s,
        @settings.beneficiary_name.first(70),
        @settings.iban,
        "", "", "",
        communication
      ].join("\n")
    end

    # SVG inline, carré, sans dimensions fixes : il prend la taille de son
    # conteneur à l'impression. Niveau de correction M, marge de 4 modules.
    def to_svg
      RQRCode::QRCode.new(payload, level: :m).as_svg(
        color: "000", shape_rendering: "crispEdges", module_size: 4,
        standalone: true, use_path: true, viewbox: true, svg_attributes: { class: "epc-qr" }
      ).sub(/\A<\?xml[^>]*\?>/, "")
    end
  end
end
