-- 7
SELECT reclada_object.create_subclass('{
    "class": "RecladaObject",
    "attributes": {
        "newClass": "Component",
        "properties": {
            "name": {"type": "string"},
            "commitHash": {"type": "string"},
            "repository": {"type": "string"}
        },
        "required": ["name","commitHash","repository"]
    }
}'::jsonb);
