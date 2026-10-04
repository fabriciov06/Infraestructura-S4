const {
    S3Client,
    GetObjectCommand,
    PutObjectCommand
} = require("@aws-sdk/client-s3");

const sharp = require("sharp");

const s3Client = new S3Client({});

/**
 * Convierte el contenido recibido desde S3
 * en un Buffer para poder procesarlo con Sharp.
 */
async function streamToBuffer(stream) {
    const chunks = [];

    for await (const chunk of stream) {
        chunks.push(
            Buffer.isBuffer(chunk)
                ? chunk
                : Buffer.from(chunk)
        );
    }

    return Buffer.concat(chunks);
}

/**
 * Decodifica el nombre del archivo recibido
 * desde un evento de S3.
 */
function decodeS3Key(key) {
    return decodeURIComponent(
        key.replace(/\+/g, " ")
    );
}

/**
 * Convierte:
 * uploads/foto.jpg
 *
 * en:
 * processed/foto_circular.png
 */
function createProcessedKey(originalKey) {

    const uploadPrefix =
        process.env.UPLOAD_PREFIX || "uploads/";

    const processedPrefix =
        process.env.PROCESSED_PREFIX || "processed/";

    let fileName = originalKey;

    if (fileName.startsWith(uploadPrefix)) {
        fileName =
            fileName.substring(uploadPrefix.length);
    }

    const extensionPosition =
        fileName.lastIndexOf(".");

    if (extensionPosition > 0) {
        fileName =
            fileName.substring(
                0,
                extensionPosition
            );
    }

    return `${processedPrefix}${fileName}_circular.png`;
}

/**
 * Procesa una imagen individual.
 */
async function processImage(s3Record) {

    const bucket =
        s3Record.s3.bucket.name;

    const key =
        decodeS3Key(
            s3Record.s3.object.key
        );

    const expectedBucket =
        process.env.IMAGE_BUCKET_NAME;

    const uploadPrefix =
        process.env.UPLOAD_PREFIX || "uploads/";

    /*
     * Verifica que el mensaje corresponda
     * al bucket configurado.
     */
    if (
        expectedBucket &&
        bucket !== expectedBucket
    ) {
        throw new Error(
            `Bucket no permitido: ${bucket}`
        );
    }

    /*
     * Solo procesa archivos de uploads/.
     */
    if (!key.startsWith(uploadPrefix)) {

        console.log(
            `Archivo ignorado: ${key}`
        );

        return;
    }

    console.log(
        `Procesando: s3://${bucket}/${key}`
    );

    // 1. Descargar imagen original desde S3
    const response =
        await s3Client.send(
            new GetObjectCommand({
                Bucket: bucket,
                Key: key
            })
        );

    const originalImage =
        await streamToBuffer(
            response.Body
        );

    // 2. Crear máscara circular de 40x40
    const circularMask =
        Buffer.from(`
            <svg width="40" height="40">
                <circle
                    cx="20"
                    cy="20"
                    r="20"
                    fill="white"
                />
            </svg>
        `);

    // 3. Procesar imagen con Sharp
    const processedImage =
        await sharp(originalImage)

            .resize(40, 40, {
                fit: "cover",
                position: "centre"
            })

            .ensureAlpha()

            .composite([
                {
                    input: circularMask,
                    blend: "dest-in"
                }
            ])

            .png()

            .toBuffer();

    // 4. Generar nombre para processed/
    const processedKey =
        createProcessedKey(key);

    // 5. Guardar imagen procesada
    await s3Client.send(
        new PutObjectCommand({
            Bucket: bucket,
            Key: processedKey,
            Body: processedImage,
            ContentType: "image/png"
        })
    );

    console.log(
        `Imagen procesada: s3://${bucket}/${processedKey}`
    );
}

/**
 * Handler principal de Lambda.
 * Es disparado mediante eventos SQS.
 */
exports.handler = async (event) => {

    console.log(
        `Mensajes recibidos desde SQS: ${event.Records?.length || 0}`
    );

    const batchItemFailures = [];

    for (const sqsRecord of event.Records || []) {

        try {

            /*
             * El body del mensaje SQS contiene
             * el evento generado por S3.
             */
            let body =
                JSON.parse(
                    sqsRecord.body
                );

            /*
             * También permite S3 -> SNS -> SQS.
             */
            if (body.Message) {
                body =
                    JSON.parse(
                        body.Message
                    );
            }

            /*
             * Evento especial que puede enviar S3.
             */
            if (
                body.Event === "s3:TestEvent"
            ) {
                console.log(
                    "Evento de prueba S3 recibido"
                );

                continue;
            }

            const s3Records =
                body.Records || [];

            for (const s3Record of s3Records) {

                await processImage(
                    s3Record
                );
            }

        } catch (error) {

            console.error(
                `Error procesando mensaje ${sqsRecord.messageId}`,
                error
            );

            batchItemFailures.push({
                itemIdentifier:
                sqsRecord.messageId
            });
        }
    }

    return {
        batchItemFailures
    };
};