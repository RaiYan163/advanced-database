# Topic 14: Installing Local MongoDB and Using It from Flask

This topic reuses the CRUD app structure from Topic 12, but points it at a local MongoDB server running in your Codespace instead of MongoDB Atlas.

## Goals

- install MongoDB locally in a Codespace
- connect a Flask app to the local server with `pymongo`
- keep the same CRUD flow for pets and owners
- use a real MongoDB instance without depending on a cloud demo cluster that may or may not cooperate today

## Files

- `install.sh` installs MongoDB, starts `mongod`, creates the admin user, creates the app user, and seeds `pets_demo.pets`
- `database.py` connects to local MongoDB using `pymongo`
- `app.py` runs the Flask CRUD app
- `templates/` contains the CRUD templates copied from Topic 12

## Requirements

Install Python packages:

```bash
pip3 install -r requirements.txt
```

## First-Time Setup

Run the installer with passwords for the admin and app users:

```bash
MONGO_ADMIN_PASSWORD='choose-a-real-password' \
MONGO_APP_PASSWORD='choose-another-real-password' \
./install.sh
```

## Run the App

Export the application password so `database.py` can authenticate as `petsApp`:

```bash
export MONGO_APP_PASSWORD='choose-another-real-password'
python3 app.py
```

Optional overrides:

```bash
export MONGO_HOST=127.0.0.1
export MONGO_PORT=27017
export MONGO_DB=pets_demo
export MONGO_APP_USERNAME=petsApp
export MONGO_AUTH_DB=pets_demo
```

If you set `MONGO_URI`, the app uses that directly.

## Notes

- This app uses two collections: `pets` and `owners`.
- The data layer returns document IDs as strings for use in URLs.
- Validation is still handled in `database.py`.
- The app user only gets `readWrite` on `pets_demo`, which is much less reckless than using the admin account for everything.
