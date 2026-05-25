$modelname "ladevasta/powerplants/coolingtower_1.mdl"

$body "Body" "coolingtower_1.smd"

$staticprop
$mostlyopaque

$surfaceprop "concrete"
$contents "solid"

$cdmaterials "models/ladevasta/powerplants"

$sequence "idle" "coolingtower_1.smd" fps 1

// Static props are lit by the map compiler as props, not brush lightmapped surfaces.
// For a very large model, prefer func_detail/world collision in Hammer if this mesh is too heavy.
$collisionmodel "coolingtower_1_phys.smd"
{
    $mass 100000
	$concave
	$remove2d
	$maxconvexpieces 1000000
}
