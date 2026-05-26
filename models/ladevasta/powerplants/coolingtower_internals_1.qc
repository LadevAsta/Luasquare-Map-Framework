$modelname "ladevasta/powerplants/coolingtower_internals_1.mdl"

$body "Body" "coolingtower_internals_1.smd"

$staticprop
$mostlyopaque

$surfaceprop "concrete"
$contents "solid"

$cdmaterials "models/ladevasta/powerplants"

$sequence "idle" "coolingtower_internals_1.smd" fps 1

$collisionmodel "coolingtower_internals_1_phys.smd"
{
    $mass 100000
	$concave
	$remove2d
	$maxconvexpieces 1000000
}
