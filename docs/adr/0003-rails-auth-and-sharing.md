# 0003. Rails authentication, multi-user readiness, folder sharing

## Status

Accepted

## Context

The app will be multi-user. Personal GTD lists stay private. Collaboration is optional
and should not imply shared inboxes or full team PM. We considered per-project
memberships, org tenancy, and no-login shortcuts. With **project folders** as the
filing tree (ADR 0009), the natural share unit is the **folder**: grant access once
and cover a whole subtree of folders and projects.

## Decision

### Auth

- **Standard Rails authentication** from Phase 0 (`bin/rails generate authentication`).
- Session-based email + password as generated; require sign-in for app features.
- Prefer the Rails generator over **Devise** unless a concrete need appears (OAuth, etc.).

### Multi-user data

- Personal resources `belongs_to :user` (`null: false`, indexed FK) from the first models.
- Always scope personal lists by `current_user`.
- Never assume a global inbox or next-actions table without `user_id` / access rules.

### Sharing unit: project folders (later feature, design now)

- **Share a project folder**, not an individual project as the primary mechanism.
- Sharing a folder grants access to:
  - that folder,
  - **all nested subfolders** (descendant folders),
  - **all projects** filed in that folder or any descendant folder,
  - and thus the **tasks** (outliner trees) under those projects, per authz rules.
- Implementation sketch: `folder_memberships` (folder, user, role) on the **shared root**
  folder; effective access = member of a folder that is an **ancestor** of the
  project’s folder (or of the folder being viewed), or owner.
- **Owner** remains on the folder tree / projects as today (`user_id` / `owner_id`);
  members get access via membership on a shared ancestor folder.
- **Unfiled projects** (no folder): not covered by folder share. Options later: require
  filing to share, or a one-off “share this project” that creates/moves into a shared
  folder — prefer **file under a folder and share the folder** for v1 of sharing.
- Personal **inbox**, personal tasks outside shared projects, **tags** (personal trees),
  and per-user agenda semantics stay private unless the task/project is reachable via
  shared folder access.
- **No** organization/personal-org multi-database tenancy (ADR 0002).
- Not in early MVP phases: full team PM, chat, SSO, org workspaces.

### Authorization

- Until sharing ships: owner-only on all personal data.
- When sharing ships: can_read/write project or folder if owner **or** member of an
  ancestor shared folder (roles e.g. viewer/editor as needed).
- No complex ACL framework in Phase 0.
- Tests: isolation (User A cannot read User B’s private data); folder share cascades to
  nested folders and projects; unfiled project not visible via unrelated shares.

### Open product detail (when implementing sharing)

- Whether shared-project next actions appear on each member’s personal Next list or
  only under shared folder/project views (still open).
- Exact roles and who may re-share or invite.

## Consequences

- Phase 0 includes real User/Session, not a stub single-user mode.
- Schema readiness: folders and projects owned by user; membership table lands with
  sharing phase — no need for per-project membership as the primary model.
- Sharing UX centers on **folders** (“Share Work/Client A…”).
- Moving a project **into** a shared folder grants access; moving **out** revokes
  cascade access (document carefully in UI).
- Orgs as a product noun remain optional later (new ADR), not required for this model.
