"""
Player details added by onboarding v2: shirt name and number, town, level,
goal, playing style, weaker foot, and the guardian's phone.

A NEW table (`player_details`) that points at `users`, instead of new columns
on `profiles`: Tracka creates tables on start-up (`create_all`) and has no
migration tool yet, so adding columns to an existing table wouldn't reach
databases that already exist. New tables always do. See CLAUDE.md
("new tables that point at users") and docs/handbook/02-designing-a-system.md.

Private by default: `town` and the guardian's phone are never shown to other
players; only the region is (see the privacy policy draft).
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import (
    JSON,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Table,
    delete,
    insert,
    select,
    update,
)

from .. import db

LEVELS = ("fun", "amateur", "school", "club", "academy", "pro")
GOALS = ("fun", "school", "academy", "standout", "better", "looking")
# Goals where the player isn't building a scouting profile: no positions needed, casual setup.
CASUAL_GOALS = ("fun", "looking")

player_details = Table(
    "player_details",
    db.metadata,
    Column("user_id", String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("shirt_name", String(20)),
    Column("shirt_number", Integer),
    Column("town", String(60)),  # private: only the region is ever shown
    Column("level", String(12)),  # fun | amateur | school | club | academy | pro
    Column("goal", String(12)),  # fun | school | academy | standout | better | looking
    Column("style", String(40)),  # how the player sees their game ("Playmaker")
    Column("weak_foot", Integer),  # 1 (hard to use) … 5 (strong as my best)
    Column("guardian_phone", String(24)),  # private: for guardian approval texts (coming)
    Column("guardian_relation", String(12)),  # parent | guardian | coach
    Column("casual", JSON),  # casual setup: how often, kinds of games, what would help
    Column("updated_at", DateTime(timezone=True), nullable=False),
)

FIELDS = (
    "shirt_name",
    "shirt_number",
    "town",
    "level",
    "goal",
    "style",
    "weak_foot",
    "guardian_phone",
    "guardian_relation",
    "casual",
)


def get(uid: str) -> dict[str, Any]:
    with db.engine().connect() as c:
        row = c.execute(select(player_details).where(player_details.c.user_id == uid)).first()
    if row is None:
        return dict.fromkeys(FIELDS)
    return {k: row._mapping[k] for k in FIELDS}


def save(uid: str, values: dict[str, Any]) -> dict[str, Any]:
    values = {k: v for k, v in values.items() if k in FIELDS}
    if not values:
        return get(uid)
    with db.engine().begin() as c:
        exists = c.execute(select(player_details.c.user_id).where(player_details.c.user_id == uid)).first()
        if exists:
            c.execute(
                update(player_details)
                .where(player_details.c.user_id == uid)
                .values(**values, updated_at=db.now())
            )
        else:
            c.execute(insert(player_details).values(user_id=uid, updated_at=db.now(), **values))
    return get(uid)


def delete_for(uid: str) -> None:
    with db.engine().begin() as c:
        c.execute(delete(player_details).where(player_details.c.user_id == uid))
