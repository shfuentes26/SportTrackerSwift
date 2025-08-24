# SportTrackerSwift

SportTrackerSwift is an iOS fitness‑tracking application built with **SwiftUI** and **SwiftData**.  
It allows you to log strength workouts and running sessions, view a weekly activity summary, set goals, and store all information locally (with support for remote synchronisation in the future).

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Architecture and project structure](#architecture-and-project-structure)
4. [Requirements & getting started](#requirements--getting-started)
5. [Contribution guide](#contribution-guide)
6. [License](#license)

## Overview

SportTrackerSwift started as a personal project to keep track of weekly workouts.  
It is organised using **SwiftUI** with a lightweight **MVVM** architecture that separates data models, business logic and views.  
It leverages **SwiftData** to persistently store all exercises, strength sessions, runs and user settings.  
The app can also query Apple Health to import workouts created in other apps, and it is prepared to synchronise data with a remote backend (using the `remoteId` and `syncState` fields).

## Features

- **Summary view**: see at a glance the workouts completed during the week, progress indicators and goal rings for calories or exercise points.  
- **Gym (strength workouts)**: create and manage strength sessions composed of multiple sets. Each set stores repetitions, weight and rest time.  
- **Running**: log runs with the ability to display the route on a map and calculate distance, pace and points.  
- **New training**: create new running or strength sessions from this view.  
- **Settings**: configure user preferences (display name, metric/imperial units, etc.).  
- **Apple Health integration**: import and synchronise workouts created through the Health app.  
- **Local persistence with SwiftData**: the models `UserProfile`, `Settings`, `Exercise`, `StrengthSet`, `StrengthSession` and `RunningSession` are stored in a data container managed by the `Persistence` class.  
- **Modular architecture**: the code is organised into `Data`, `Domain` and `Features` modules to facilitate scalability and maintenance.

## Architecture and project structure

The project is divided into three main layers:

| Folder        | Contents                                                                                          |
|---------------|---------------------------------------------------------------------------------------------------|
| **Data**      | Persistent models (`@Model`) and repositories that handle reading/writing data.                   |
| **Domain**    | Business logic independent of the user interface (e.g., points calculation).                      |
| **Features**  | Views and ViewModels organised by functionality: **Gym**, **Running**, **Summary**, **Settings** and **NewTraining**. |
| **Resources** | Icons, assets, launch stories and other app resources.                                             |

Each view uses a **ViewModel** that acts as an intermediary between the UI and the data repositories. Repetitive operations like listing, saving or deleting are implemented in specific repositories (`RunningRepository`, `StrengthRepository`) following a clean, testable pattern.

## Requirements & getting started

To build and run the project you need:

- Xcode 15 or newer on a Mac running macOS Ventura or later.  
- iOS 17 or later (the project uses SwiftUI APIs from iOS 17).  
- HealthKit permissions if you wish to import external workouts from Apple Health.  

### Clone and run the project

1. Clone this repository: `git clone https://github.com/shfuentes26/SportTrackerSwift.git`  
2. Open the `SportTracker.xcodeproj` file in Xcode.  
3. Select the **SportTracker** scheme and run it on a simulator or physical device.  
4. The first time you launch the app, basic sample data (basic exercises and initial settings) will automatically be populated via the `makeModelContainer()` method in `Persistence.swift`.

## Contribution guide

Contributions are welcome! If you would like to help:

1. **Fork** the repository and clone it locally.  
2. Create a descriptive branch (e.g. `feature/new-chart` or `bugfix/fix-week-start`).  
3. Ensure that your code follows a **consistent language convention** (use English for variable names, methods and comments).  
4. If you introduce a new view, create an associated ViewModel and maintain separation of responsibilities according to MVVM.  
5. Open a **pull request** detailing your improvements and respond to any review comments.  

### Code style

- Prefer descriptive names in English for variables and functions.  
- Add concise documentation when the logic is not obvious.  
- Use generic repositories when multiple entities share the same persistence logic (for example, `list()`, `save()`, `delete()`).  
- Manage errors with `do/catch` and show user‑friendly messages in the interface.  
- Use **SwiftLint** to maintain code style consistency.

## License

This project is published under the MIT license.  
See the `LICENSE` file for more information.
