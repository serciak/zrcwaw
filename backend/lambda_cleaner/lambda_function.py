import os
import json
import psycopg2
import boto3
import logging

# -----------------------------
# Logging configuration
# -----------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Optional: include timestamp + log level
formatter = logging.Formatter(
    "%(asctime)s - %(levelname)s - %(message)s"
)
for handler in logger.handlers:
    handler.setFormatter(formatter)

# -----------------------------
# Environment variables
# -----------------------------
DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]
S3_BUCKET = os.environ["S3_BUCKET"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

s3 = boto3.client("s3", region_name=AWS_REGION)


def lambda_handler(event, context):
    logger.info("=== Lambda execution started ===")
    logger.info(f"Incoming event: {json.dumps(event)}")

    # Log context details
    logger.info(f"Request ID: {context.aws_request_id}")
    logger.info(f"Function name: {context.function_name}")
    logger.info(f"Memory limit: {context.memory_limit_in_mb} MB")

    deleted_todos = 0
    deleted_files = 0

    # -----------------------------
    # Connect to PostgreSQL
    # -----------------------------
    logger.info(
        f"Connecting to RDS: host={DB_HOST}, db={DB_NAME}, user={DB_USER}"
    )

    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
        )
        logger.info("Successfully connected to RDS.")
    except Exception as e:
        logger.error("Failed to connect to database!")
        logger.exception(e)
        raise

    try:
        with conn.cursor() as cur:
            logger.info("Fetching todos marked as completed...")

            cur.execute("SELECT id, image_key FROM todos WHERE completed = TRUE")
            rows = cur.fetchall()

            logger.info(f"Found {len(rows)} completed todos.")

            todo_ids = [r[0] for r in rows]
            image_keys = [r[1] for r in rows if r[1] is not None]

            logger.info(f"Todo IDs to delete: {todo_ids}")
            logger.info(f"S3 keys to delete: {image_keys}")

            # -----------------------------
            # Delete todos from DB
            # -----------------------------
            if todo_ids:
                cur.execute("DELETE FROM todos WHERE id = ANY(%s)", (todo_ids,))
                deleted_todos = cur.rowcount
                logger.info(f"Deleted {deleted_todos} todos from the database.")
            else:
                logger.info("No todos to delete.")

            # -----------------------------
            # Delete S3 objects in batches
            # -----------------------------
            if image_keys:
                objects = [{"Key": key} for key in image_keys]

                logger.info(f"Deleting {len(objects)} objects from S3...")

                for i in range(0, len(objects), 1000):
                    chunk = objects[i : i + 1000]
                    logger.info(f"Deleting S3 chunk of size {len(chunk)}")

                    try:
                        resp = s3.delete_objects(
                            Bucket=S3_BUCKET,
                            Delete={"Objects": chunk, "Quiet": True},
                        )
                        deleted_count = len(resp.get("Deleted", []))
                        deleted_files += deleted_count

                        logger.info(
                            f"S3 deletion response: deleted={deleted_count}, "
                            f"errors={resp.get('Errors', [])}"
                        )
                    except Exception as e:
                        logger.error("S3 deletion failed!")
                        logger.exception(e)
                        raise

            else:
                logger.info("No S3 files to delete.")

        # Commit the DB transaction
        conn.commit()
        logger.info("Database commit successful.")

    except Exception as e:
        logger.error("Error inside main try block:")
        logger.exception(e)
        raise

    finally:
        conn.close()
        logger.info("Database connection closed.")

    # -----------------------------
    # Summary
    # -----------------------------
    logger.info(
        f"=== Lambda execution completed === "
        f"Deleted todos: {deleted_todos}, Deleted files: {deleted_files}"
    )

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "deleted_todos": deleted_todos,
                "deleted_files": deleted_files,
            }
        ),
    }
