const functions = require('firebase-functions');
const axios = require('axios');

exports.validateReceipt = functions.https.onRequest(async (req, res) => {
  const { platform, receipt, productId, type } = req.body;

  try {
    if (platform === 'ios') {
      const response = await axios.get(
        `https://api.storekit.itunes.apple.com/inApps/v1/transactions/${receipt}`,
        {
          headers: {
            Authorization: `Bearer ${process.env.APPLE_API_TOKEN}`,
          },
        }
      );

      const transaction = response.data;
      const isValid = transaction.signedDate &&
                      transaction.productId === productId &&
                      (type === 'consumable' ? transaction.type === 'Consumable' : transaction.type === 'Auto-Renewable Subscription');
      res.status(200).json({
        isValid,
        expiresDate: transaction.expiresDate || null,
        productId,
        type,
      });
    } else if (platform === 'android') {
      const accessToken = await getGoogleAccessToken();
      const endpoint = type === 'consumable'
        ? `purchases/products/${productId}/tokens/${receipt}`
        : `purchases/subscriptions/${productId}/tokens/${receipt}`;
      const response = await axios.get(
        `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${process.env.ANDROID_PACKAGE_NAME}/${endpoint}`,
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        }
      );

      const purchase = response.data;
      const isValid = type === 'consumable'
        ? purchase.paymentState === 1
        : purchase.paymentState === 1 && purchase.autoRenewing;
      res.status(200).json({
        isValid,
        expiresDate: purchase.expiryTimeMillis || null,
        productId,
        type,
      });
    } else {
      throw new Error('Invalid platform');
    }
  } catch (error) {
    console.error('Validation error:', error);
    res.status(500).json({ isValid: false, error: error.message, productId, type });
  }
});

async function getGoogleAccessToken() {
  const response = await axios.post('https://accounts.google.com/o/oauth2/token', {
    grant_type: 'refresh_token',
    client_id: process.env.GOOGLE_CLIENT_ID,
    client_secret: process.env.GOOGLE_CLIENT_SECRET,
    refresh_token: process.env.GOOGLE_REFRESH_TOKEN,
  });
  return response.data.access_token;
}