# Le formulaire de relevé de dépôt-vente, partagé par ses deux portes : le lien
# mensuel à jeton (`Public::ConsignmentReportsController`) et l'espace artisan
# du portail (`Portal::ConsignorReportsController`) — epic #359, phase 2.
#
# Une seule liste de champs permis, une seule conversion des euros tapés au
# téléphone (« 4,50 ») en centimes : les deux saisies ne peuvent pas diverger.
module ConsignmentReportForm
  extend ActiveSupport::Concern

  LINE_FIELDS = %i[id label quantity unit_price_euros position payment_method catalog_item_id _destroy].freeze

  private

  def consignment_report_params(*extra)
    params.require(:consignment_report).permit(
      :notes, *extra, photos: [],
      consignment_report_lines_attributes: LINE_FIELDS
    ).tap do |permitted|
      lines = permitted[:consignment_report_lines_attributes]
      next if lines.blank?

      lines.each_value do |line|
        euros = line.delete(:unit_price_euros)
        line[:unit_price_cents] = (euros.to_s.tr(",", ".").to_f * 100).round if euros.present?
      end
    end
  end

  # Les articles proposés dans le sélecteur : les produits actifs de l'artisan,
  # plus ceux, désactivés depuis, qu'une ligne du relevé cite encore — sinon la
  # ligne perdrait son article à la prochaine sauvegarde.
  def consignment_products_for(consignor, report)
    cited = report.consignment_report_lines.map(&:catalog_item_id).compact
    consignor.catalog_items.craft
             .where(active: true).or(consignor.catalog_items.craft.where(id: cited))
             .includes(:catalog_prices).order(:name)
  end
end
