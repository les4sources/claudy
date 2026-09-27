# Les notes manuscrites de la carte (epic #348, phase 12), en JSON pour le
# module `map_sketches.js`.
#
# - `index` : la liste du panneau (dossier, nom, nombre de tracés), SANS les
#   tracés — un dessin peut peser lourd ;
# - `show` : les tracés d'un dessin, chargés quand on l'affiche ;
# - `create` / `update` / `destroy` : créer, renommer ou changer de dossier,
#   supprimer (en douceur) ;
# - `strokes` : REMPLACE les tracés d'un bloc (enregistrement automatique du
#   client, 500 ms après le dernier trait). Le client renvoie la `lock_version`
#   qu'il a lue : si le dessin a changé ailleurs entre-temps (autre appareil,
#   autre onglet, renommage), on répond 409 avec la version courante, sans rien
#   écrire, et le client recharge le dessin.
class MapSketchesController < BaseController
  before_action :get_sketch, only: %i[show update destroy strokes]

  def index
    render json: MapSketch.ordered.map(&:as_summary)
  end

  def show
    render json: @sketch.as_detail
  end

  def create
    sketch = MapSketch.new(sketch_params.merge(created_by: current_user))
    if sketch.save
      render json: sketch.as_detail, status: :created
    else
      render json: { errors: sketch.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @sketch.update(sketch_params)
      render json: @sketch.as_summary
    else
      render json: { errors: @sketch.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @sketch.soft_delete!(validate: false)
    head :no_content
  end

  # PATCH /map/sketches/:id/strokes — { strokes: [...], lock_version: n }
  def strokes
    body = request.request_parameters
    version = body["lock_version"]
    unless version.is_a?(Integer) || version.to_s.match?(/\A\d+\z/)
      return render json: { errors: ["La version du dessin est obligatoire"] }, status: :unprocessable_content
    end

    # La version lue par le client : Rails la met dans le WHERE de l'UPDATE et
    # lève `StaleObjectError` si la base en a une autre.
    @sketch.lock_version = version.to_i
    @sketch.strokes = body["strokes"]
    if @sketch.save
      render json: @sketch.as_summary
    else
      render json: { errors: @sketch.errors.full_messages }, status: :unprocessable_content
    end
  rescue ActiveRecord::StaleObjectError
    render json: { errors: ["Ce dessin a été modifié ailleurs"], lock_version: @sketch.reload.lock_version },
           status: :conflict
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_sketch
    @sketch = MapSketch.find_by(id: params[:id])
    head :not_found unless @sketch
  end

  def sketch_params
    params.require(:map_sketch).permit(:name, :folder)
  end
end
