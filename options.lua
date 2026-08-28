return {
  {
    key = "pc_menu_position",
    label = "SHOW IN PC MENU",
    type = "choice",
    default = "end",
    choices = {
      { "NONE", "none", "Row hidden from\nthe PC menu." },
      { "START", "start", "Row is first in\nthe PC menu." },
      { "MIDDLE", "middle", "Sits below\nBILL's/Someone's." },
      { "END", "end", "Sits below\nyour own PC." },
    }
  },
  {
    key = "show_pokemon_tab",
    label = "POKéMON MENU",
    type = "toggle",
    default = true,
    onHint = "Tab shows up.",
    offHint = "Tab is hidden."
  },
  {
    key = "show_items_tab",
    label = "ITEMS MENU",
    type = "toggle",
    default = true,
    onHint = "Tab shows up.",
    offHint = "Tab is hidden."
  },
  {
    key = "show_moves_tab",
    label = "MOVES MENU",
    type = "toggle",
    default = true,
    onHint = "Tab shows up.",
    offHint = "Tab is hidden."
  },
  {
    key = "show_money_tab",
    label = "MONEY MENU",
    type = "toggle",
    default = true,
    onHint = "Tab shows up.",
    offHint = "Tab is hidden."
  },
  {
    key = "show_link_tab",
    label = "LINK MENU",
    type = "toggle",
    default = true,
    onHint = "Tab shows up.",
    offHint = "Tab is hidden."
  },
  {
    key = "box_size",
    label = "BOX SIZE",
    type = "choice",
    default = "20",
    choices = {
      { "20", "20", "Holds 20\nPOKéMON per box." },
      { "30", "30", "Holds 30\nPOKéMON per box." },
      { "NO LIMIT", "-1", "No limit on\nPOKéMON per box." },
    }
  },
  {
    key = "empty_box_deletion",
    label = "DELETE EMPTY BOX",
    type = "choice",
    default = "unnamed",
    choices = {
      { "ALL", "all", "Empty boxes\nalways removed." },
      { "UNNAMED", "unnamed", "Unnamed empty\nboxes removed." },
      { "NEVER", "never", "Empty boxes\nare kept." },
    }
  },
  {
    key = "inherit_trainer_on_withdraw",
    label = "INHERIT TRAINER",
    type = "toggle",
    default = false,
    onHint = "You become OT\non withdraw.",
    offHint = "OT stays\nunchanged."
  },
  {
    key = "legality_checks",
    label = "LEGALITY CHECKS",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off", "No legality\ncheck made." },
      { "FIX", "fix", "Asks to fix an\nillegal POKéMON." },
      { "FORCE FIX", "force_fix", "Fixes it without\nasking first." },
      { "REJECT", "reject", "Refuses an\nillegal POKéMON." },
    }
  },
  {
    key = "storage_mode",
    label = "STORAGE MODE",
    type = "choice",
    default = "bank",
    choices = {
      { "BANK", "bank", "Only MANAGE\n<PK><MN> shows." },
      { "TIME CAPSULE", "time_capsule", "Only TIME\nCAPSULE shows." },
      { "BOTH", "both", "Chooser: <PK><MN>,\nBOX, CAPSULE." },
    }
  },
  {
    key = "auto_heal",
    label = "AUTO HEAL",
    type = "choice",
    default = "never",
    choices = {
      { "NEVER", "never", "Never heals\nthe Bank." },
      { "ON DEPOSIT", "deposit", "Heals on\ndeposit." },
      { "ON WITHDRAW", "withdraw", "Heals on\nwithdraw." },
      { "AT POKéMON CENTER", "center", "Heals at the\nPOKéMON CENTER." },
    }
  },
  {
    key = "quarantine_notice",
    label = "REPORT MODE",
    type = "choice",
    default = "report",
    choices = {
      { "NONE", "none", "No load\nnotice shown." },
      { "MESSAGE", "message", "Shows a short\nmessage." },
      { "FULL", "report", "Shows the\nREPORT screen." },
    }
  }
}
