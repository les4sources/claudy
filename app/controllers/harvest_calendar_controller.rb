# Le calendrier des récoltes (epic #348, phase 7) : douze mois, et dans chacun
# ce qui se récolte au domaine — « Pommier Reinette Hernaut — fruit ». Les
# individus d'une même espèce se regroupent (« Pommier ×12 — fruit »), dépliables.
#
# Même règle d'héritage que la fiche : une plante sans fenêtre propre suit
# celles de son espèce (`Plant.harvest_calendar`, sans N+1). Les plantes mortes
# ne se récoltent plus. Filtres partie et zone, dans l'URL.
class HarvestCalendarController < BaseController
  access_section :map
  # Une ligne du mois : une espèce (ou une plante sans espèce) et une partie.
  Group = Struct.new(:key, :title, :part, :plants, keyword_init: true) do
    def single? = plants.one?
    def part_label = PlantHarvestWindow.part_label(part)
  end

  def index
    @part = params[:part].presence_in(PlantHarvestWindow::PARTS.keys)
    @zones = Plant.alive.zones
    @zone = params[:zone].presence_in(@zones)
    @current_month = Date.current.month

    calendar = Plant.in_zone(@zone).harvest_calendar(part: @part)
    @groups_by_month = calendar.transform_values { |entries| group(entries) }
    @plant_counts = calendar.transform_values { |entries| entries.map(&:first).uniq.size }
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def group(entries)
    parts = PlantHarvestWindow::PARTS.keys
    entries.group_by { |plant, window| [plant.plant_species_id ? "species-#{plant.plant_species_id}" : "plant-#{plant.id}", window.part] }
           .map do |(key, part), pairs|
             plants = pairs.map(&:first).uniq.sort_by { |plant| [plant.number || Float::INFINITY, plant.display_name.downcase] }
             species = plants.first.plant_species
             Group.new(key: "#{key}-#{part}", part: part, plants: plants,
                       title: plants.one? ? plants.first.display_name : species&.name || plants.first.display_name)
           end
           .sort_by { |group| [group.title.downcase, parts.index(group.part)] }
  end
end
