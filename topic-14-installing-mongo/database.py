import os
import uuid

from bson.objectid import ObjectId
from pymongo import MongoClient


client = None
db = None
owners_collection = None
pets_collection = None


class NotFoundError(LookupError):
    pass


class ConstraintError(ValueError):
    pass


def _mongo_settings(database_name=None):
    db_name = database_name or os.environ.get("MONGO_DB", "pets_demo")
    host = os.environ.get("MONGO_HOST", "127.0.0.1")
    port = int(os.environ.get("MONGO_PORT", "27017"))
    username = os.environ.get("MONGO_APP_USERNAME", "petsApp")
    password = os.environ.get("MONGO_APP_PASSWORD", "")
    auth_db = os.environ.get("MONGO_AUTH_DB", db_name)
    uri = os.environ.get("MONGO_URI", "").strip()

    return {
        "db_name": db_name,
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "auth_db": auth_db,
        "uri": uri,
    }


def initialize(database_name=None):
    global client, db, owners_collection, pets_collection

    close_connection()
    settings = _mongo_settings(database_name)

    if settings["uri"]:
        client = MongoClient(settings["uri"])
    elif settings["password"]:
        client = MongoClient(
            host=settings["host"],
            port=settings["port"],
            username=settings["username"],
            password=settings["password"],
            authSource=settings["auth_db"],
        )
    else:
        client = MongoClient(host=settings["host"], port=settings["port"])

    db = client[settings["db_name"]]
    owners_collection = db.owners
    pets_collection = db.pets


def setup_database(database_name=None):
    """
    Prepare the local Mongo database and ensure the collections exist.

    MongoDB creates collections lazily, so touching them here is enough to
    force initialization on a fresh database.
    """

    initialize(database_name)
    owners_collection.count_documents({})
    pets_collection.count_documents({})


def close_connection():
    global client, db, owners_collection, pets_collection

    if client is not None:
        try:
            client.close()
        except Exception:
            pass
    client = None
    db = None
    owners_collection = None
    pets_collection = None


def _normalize_age(value):
    try:
        return int(value)
    except Exception:
        return 0


def _require_text(value, field_name):
    text = (value or "").strip()
    if text == "":
        raise ValueError(f"{field_name} is required.")
    return text


def _to_object_id(value, field_name="id"):
    try:
        return ObjectId(str(value))
    except Exception as exc:
        raise ValueError(f"{field_name} must be a valid ObjectId string.") from exc


def _require_owner(owner_id):
    object_id = _to_object_id(owner_id, "owner_id")
    owner = owners_collection.find_one({"_id": object_id})
    if owner is None:
        raise ConstraintError("owner_id does not reference an existing owner.")
    return object_id


def _require_existing_pet(id):
    object_id = _to_object_id(id, "pet id")
    pet = pets_collection.find_one({"_id": object_id})
    if pet is None:
        raise NotFoundError("pet not found.")
    return object_id, pet


def _require_existing_owner(id):
    object_id = _to_object_id(id, "owner id")
    owner = owners_collection.find_one({"_id": object_id})
    if owner is None:
        raise NotFoundError("owner not found.")
    return object_id, owner


def _normalize_pet_data(data):
    owner_id = data.get("owner_id")
    if (owner_id or "").strip() == "":
        raise ValueError("owner_id is required.")

    return {
        "name": _require_text(data.get("name"), "name"),
        "type": _require_text(data.get("type"), "type"),
        "age": _normalize_age(data.get("age")),
        "owner_id": _require_owner(owner_id),
    }


def _normalize_owner_data(data):
    return {
        "name": _require_text(data.get("name"), "name"),
        "city": (data.get("city") or "").strip() or None,
        "type_of_home": (data.get("type_of_home") or "").strip() or None,
    }


def pet_to_dict(pet):
    return {
        "id": str(pet["_id"]),
        "name": pet["name"],
        "type": pet["type"],
        "age": pet["age"],
        "owner_id": str(pet["owner_id"]),
    }


def owner_to_dict(owner):
    return {
        "id": str(owner["_id"]),
        "name": owner["name"],
        "city": owner.get("city"),
        "type_of_home": owner.get("type_of_home"),
    }


def get_pets():
    return [pet_to_dict(pet) for pet in pets_collection.find()]


def get_pet(id):
    object_id = _to_object_id(id, "pet id")
    pet = pets_collection.find_one({"_id": object_id})
    if pet is None:
        return None
    return pet_to_dict(pet)


def create_pet(data):
    pet = _normalize_pet_data(data)
    result = pets_collection.insert_one(pet)
    return str(result.inserted_id)


def update_pet(id, data):
    object_id, _ = _require_existing_pet(id)
    pet = _normalize_pet_data(data)
    pets_collection.update_one({"_id": object_id}, {"$set": pet})


def delete_pet(id):
    object_id, _ = _require_existing_pet(id)
    pets_collection.delete_one({"_id": object_id})


def get_owners():
    return [owner_to_dict(owner) for owner in owners_collection.find()]


def get_owner(id):
    object_id = _to_object_id(id, "owner id")
    owner = owners_collection.find_one({"_id": object_id})
    if owner is None:
        return None
    return owner_to_dict(owner)


def create_owner(data):
    owner = _normalize_owner_data(data)
    result = owners_collection.insert_one(owner)
    return str(result.inserted_id)


def update_owner(id, data):
    object_id, _ = _require_existing_owner(id)
    owner = _normalize_owner_data(data)
    owners_collection.update_one({"_id": object_id}, {"$set": owner})


def delete_owner(id):
    object_id, _ = _require_existing_owner(id)
    pet = pets_collection.find_one({"owner_id": object_id})
    if pet is not None:
        raise ConstraintError(
            "Cannot delete this owner because they have pets. Please delete their pets first."
        )

    owners_collection.delete_one({"_id": object_id})


def reset_database(database_name=None):
    settings = _mongo_settings(database_name)
    temp_client = MongoClient(
        host=settings["host"],
        port=settings["port"],
        username=settings["username"] if settings["password"] else None,
        password=settings["password"] if settings["password"] else None,
        authSource=settings["auth_db"] if settings["password"] else None,
    ) if not settings["uri"] else MongoClient(settings["uri"])

    temp_client.drop_database(settings["db_name"])
    temp_client.close()


def unique_test_database_name(prefix="pytest_ci"):
    return f"{prefix}_{uuid.uuid4().hex[:8]}"
