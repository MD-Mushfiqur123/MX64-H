# Physical Design

No technology-specific OpenROAD config is supplied because commercial PDK selection and collateral are pending.

Required flow stages:
- floorplan and macro placement
- PDN
- global placement and optimization
- CTS
- global routing
- detailed routing
- extraction and STA
- DRC/LVS/antenna/density/IR-EM signoff
- GDSII/OASIS stream-out

Use foundry-approved signoff decks and tools. Open-source flow completion alone does not imply foundry signoff.
