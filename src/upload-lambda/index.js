const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const s3 = new S3Client();

exports.handler = async (event) => {
    try {
        console.log("Evento recibido:", JSON.stringify(event));

        const bucketName = process.env.BUCKET_NAME;
        if (!bucketName) {
            throw new Error("La variable de entorno BUCKET_NAME no está configurada.");
        }

        let body = event.body;
        if (event.isBase64Encoded) {
            body = Buffer.from(event.body, 'base64');
        } else {
            body = Buffer.from(event.body || '');
        }

        const filename = event.queryStringParameters && event.queryStringParameters.filename
            ? event.queryStringParameters.filename
            : `image-${Date.now()}.jpg`;

        const key = `uploads/${filename}`;

        const uploadParams = {
            Bucket: bucketName,
            Key: key,
            Body: body,
            ContentType: event.headers ? (event.headers['content-type'] || event.headers['Content-Type'] || 'image/jpeg') : 'image/jpeg'
        };

        const command = new PutObjectCommand(uploadParams);
        await s3.send(command);

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: "Imagen subida exitosamente",
                path: key
            }),
        };
    } catch (error) {
        console.error("Error al subir la imagen:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({
                message: "Error interno al procesar la subida",
                error: error.message
            }),
        };
    }
};