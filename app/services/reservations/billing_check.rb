module Reservations
  # Coordonnées de facturation du funnel (« Besoin d'une facture ? », Michael,
  # 2026-10-03), vérifiées avant d'enregistrer la demande.
  #
  # Raison sociale et adresse sont obligatoires dès qu'une facture est demandée.
  # Le numéro de TVA reste FACULTATIF (une école, une ASBL non assujettie, un
  # particulier qui veut une facture n'en ont pas) mais, s'il est donné :
  #   1. son format est contrôlé (Reservations::VatNumber) ;
  #   2. VIES le confirme. Un « inconnu de VIES » bloque, avec un message ; un
  #      VIES injoignable ne bloque JAMAIS : la demande part, marquée « non
  #      vérifié » pour l'équipe.
  #
  # Effet de bord voulu : le numéro est réécrit dans le draft sous sa forme
  # compacte, et le verdict VIES y est posé pour la note interne du séjour.
  class BillingCheck
    # Pays de l'adresse de facturation, dans l'ordre où le funnel les propose :
    # nos voisins d'abord, puis le reste de l'UE, la Suisse et le Royaume-Uni.
    COUNTRIES = {
      "BE" => "Belgique", "FR" => "France", "NL" => "Pays-Bas", "LU" => "Luxembourg",
      "DE" => "Allemagne", "AT" => "Autriche", "BG" => "Bulgarie", "CY" => "Chypre",
      "HR" => "Croatie", "DK" => "Danemark", "ES" => "Espagne", "EE" => "Estonie",
      "FI" => "Finlande", "GR" => "Grèce", "HU" => "Hongrie", "IE" => "Irlande",
      "IT" => "Italie", "LV" => "Lettonie", "LT" => "Lituanie", "MT" => "Malte",
      "PL" => "Pologne", "PT" => "Portugal", "CZ" => "Tchéquie", "RO" => "Roumanie",
      "SK" => "Slovaquie", "SI" => "Slovénie", "SE" => "Suède", "CH" => "Suisse",
      "GB" => "Royaume-Uni"
    }.freeze

    REQUIRED = {
      billing_name:    "Indiquez la raison sociale ou le nom à mettre sur la facture.",
      billing_address: "Indiquez l'adresse de facturation.",
      billing_zip:     "Indiquez le code postal.",
      billing_city:    "Indiquez la localité."
    }.freeze

    attr_reader :errors

    def initialize(draft, vies: Vies::Client.new)
      @draft = draft
      @vies = vies
      @errors = {}
    end

    def valid?
      @errors = {}
      return true unless @draft.invoice_requested

      REQUIRED.each { |field, message| @errors[field] = message if @draft.public_send(field).blank? }
      @draft.billing_country = "BE" unless COUNTRIES.key?(@draft.billing_country.to_s)
      check_vat
      @errors.empty?
    end

    private

    def check_vat
      @draft.billing_vies_status = nil
      @draft.billing_vies_name = nil
      return if @draft.billing_vat.blank?

      vat = VatNumber.normalize(@draft.billing_vat, country: @draft.billing_country)
      @draft.billing_vat = vat
      unless VatNumber.valid?(vat)
        @errors[:billing_vat] = "Ce numéro de TVA n'a pas le bon format (ex. : BE0123456789)."
        return
      end
      return @draft.billing_vies_status = "not_applicable" unless VatNumber.vies_checkable?(vat)

      result = @vies.check(vat)
      if result.invalid?
        @errors[:billing_vat] = "Ce numéro de TVA est inconnu du registre européen (VIES). " \
                                "Vérifiez-le, ou laissez le champ vide et précisez-le-nous par email."
      else
        @draft.billing_vies_status = result.status.to_s
        @draft.billing_vies_name = result.name
      end
    end
  end
end
