# Feuille de bar d'un groupe (Michael, 2026-10-13).
#
# Au bar, le groupe note ses consommations sur une feuille ; quand il la rend,
# on la photographie et on la recopie ici : une quantité par article du
# catalogue du bar, au prix public. Les lignes s'ajoutent au total du séjour,
# donc à sa facture. La photo reste jointe au séjour comme pièce justificative.
#
# Un écran pleine page plutôt qu'un bloc de la modale : on recopie une feuille
# en regardant sa photo, et la colonne de la modale est trop étroite pour
# montrer les deux côte à côte.
class StayBarSheetsController < BaseController
  before_action :set_stay

  def show
    load_sheet
  end

  def update
    service = Stays::EncodeBarSheet.new(stay: @stay, quantities: quantities_param, mode: "set")

    if service.run
      redirect_to stay_bar_sheet_path(@stay), notice: notice_for(service.report)
    else
      redirect_to stay_bar_sheet_path(@stay), alert: service.error_message(default: "Enregistrement impossible.")
    end
  end

  def add_photos
    photos = Array(params[:photos]).compact_blank
    if photos.empty?
      redirect_to stay_bar_sheet_path(@stay), alert: "Choisis au moins une photo."
    elsif photos.any? { |photo| !photo.content_type.to_s.start_with?("image/") }
      redirect_to stay_bar_sheet_path(@stay), alert: "Seules des images sont acceptées."
    else
      @stay.bar_sheet_photos.attach(photos)
      redirect_to stay_bar_sheet_path(@stay), notice: photos.size > 1 ? "#{photos.size} photos ajoutées." : "Photo ajoutée."
    end
  end

  def remove_photo
    @stay.bar_sheet_photos.find(params[:photo_id]).purge_later
    redirect_to stay_bar_sheet_path(@stay), notice: "Photo retirée."
  end

  private

  def set_stay
    @stay = Stay.find(params[:stay_id])
  end

  # Les articles proposés : les articles ACTIFS du bar, plus ceux que le séjour
  # porte déjà (un article retiré de la vente depuis reste lisible et
  # corrigeable sur la feuille qui le contient).
  def load_sheet
    @price_date = BarConsumption.price_date_for(@stay)
    @lines = @stay.bar_consumptions.includes(:catalog_item).index_by(&:catalog_item_id)
    scope = BarConsumption.catalog_items
    scope = @lines.any? ? scope.where(active: true).or(scope.where(id: @lines.keys)) : scope.active
    @items = scope.includes(:catalog_prices).order(Arel.sql("catalog_items.category NULLS LAST"), :name)
    @photos = @stay.bar_sheet_photos.attachments.includes(:blob).order(:created_at)
  end

  def quantities_param
    params.fetch(:quantities, {}).permit!.to_h
  end

  def notice_for(report)
    message = report.summary
    return message if report.unpriced.empty?

    "#{message} Sans prix au catalogue, donc non encodé : #{report.unpriced.join(', ')}."
  end

  # Même menu que la fiche séjour.
  def set_presenters; end
end
