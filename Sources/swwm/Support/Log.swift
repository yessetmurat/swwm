//
//  Log.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import os

/// swwm's log: `log stream --predicate 'subsystem == "dev.swwm.swwm"' --level debug`.
let log = Logger(subsystem: "dev.swwm.swwm", category: "events")
