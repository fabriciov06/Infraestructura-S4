const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const s3 = new S3Client();

exports.handler = async (event) => {
    try {
        console.log("Evento recibido:", JSON.stringify(event));

        // Obtener el nombre del bucket desde las variables de entorno de Terraform
        const bucketName = process.env.BUCKET_NAME;

        // Extraer el cuerpo de la petición (puede venir en base64 o texto)
        let body = event.body;
        if (event.isBase64Encoded) {
            body = Buffer.from(event.body, 'base64');
        } else {
            body = Buffer.from(event.body || '');
        }

        // Definir un nombre único para el archivo y la ruta solicitada 'uploads/'
        const filename = event.queryStringParameters && event.queryStringParameters.filename
            ? event.queryStringParameters.filename
            : `image-${Date.now()}.jpg`;

        const key = `uploads/${filename}`;

        // Parámetros para subir a S3
        const uploadParams = {
            Bucket: bucketName,
            Key: key,
            Body: body,
            ContentType: event.headers ? (event.headers['content-type'] || event.headers['Content-Type'] || 'image/jpeg') : 'image/jpeg'
        };

        // Ejecutar la subida usando AWS SDK v3
        const command = new PutObjectCommand(uploadParams);
        await s3.send(command);

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: "Imagen subida exitosamente a S3",
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