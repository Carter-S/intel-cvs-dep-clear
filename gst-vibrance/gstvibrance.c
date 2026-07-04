/* SPDX-License-Identifier: LGPL-2.1-or-later
 *
 * vibrance - NVIDIA-style "digital vibrance" video filter.
 *
 * Boosts colour saturation proportionally to how UNsaturated each pixel
 * is: muted colours pop, already-vivid colours and skin tones are left
 * mostly alone. CPU implementation (integer math), RGBA/RGBx/BGRA/BGRx.
 *
 *   gst-launch-1.0 videotestsrc ! video/x-raw,format=RGBA \
 *       ! vibrance amount=0.6 ! videoconvert ! autovideosink
 */
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <gst/gst.h>
#include <gst/video/video.h>
#include <gst/video/gstvideofilter.h>

#define PACKAGE "gst-vibrance"

GType gst_vibrance_get_type(void);

#define GST_TYPE_VIBRANCE (gst_vibrance_get_type())
G_DECLARE_FINAL_TYPE(GstVibrance, gst_vibrance, GST, VIBRANCE, GstVideoFilter)

struct _GstVibrance {
	GstVideoFilter parent;
	gdouble amount;
};

G_DEFINE_TYPE(GstVibrance, gst_vibrance, GST_TYPE_VIDEO_FILTER)

enum {
	PROP_0,
	PROP_AMOUNT,
};

#define VIBRANCE_CAPS \
	GST_VIDEO_CAPS_MAKE("{ RGBA, RGBx, BGRA, BGRx }")

static void
gst_vibrance_set_property(GObject *object, guint prop_id,
			  const GValue *value, GParamSpec *pspec)
{
	GstVibrance *self = GST_VIBRANCE(object);

	switch (prop_id) {
	case PROP_AMOUNT:
		self->amount = g_value_get_double(value);
		break;
	default:
		G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
		break;
	}
}

static void
gst_vibrance_get_property(GObject *object, guint prop_id,
			  GValue *value, GParamSpec *pspec)
{
	GstVibrance *self = GST_VIBRANCE(object);

	switch (prop_id) {
	case PROP_AMOUNT:
		g_value_set_double(value, self->amount);
		break;
	default:
		G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
		break;
	}
}

static GstFlowReturn
gst_vibrance_transform_frame_ip(GstVideoFilter *filter, GstVideoFrame *frame)
{
	GstVibrance *self = GST_VIBRANCE(filter);
	/* amount scaled to 8.8 fixed point */
	const gint32 amount_fx = (gint32)(self->amount * 256.0);
	guint8 *data = GST_VIDEO_FRAME_PLANE_DATA(frame, 0);
	const gint stride = GST_VIDEO_FRAME_PLANE_STRIDE(frame, 0);
	const gint w = GST_VIDEO_FRAME_WIDTH(frame);
	const gint h = GST_VIDEO_FRAME_HEIGHT(frame);
	/* channel offsets for RGBA/RGBx vs BGRA/BGRx */
	const GstVideoFormat fmt = GST_VIDEO_FRAME_FORMAT(frame);
	const gboolean bgr = (fmt == GST_VIDEO_FORMAT_BGRA ||
			      fmt == GST_VIDEO_FORMAT_BGRx);
	const gint ro = bgr ? 2 : 0, bo = bgr ? 0 : 2;

	if (amount_fx <= 0)
		return GST_FLOW_OK;

	for (gint y = 0; y < h; y++) {
		guint8 *px = data + y * stride;
		for (gint x = 0; x < w; x++, px += 4) {
			const gint32 r = px[ro], g = px[1], b = px[bo];
			gint32 mx = r > g ? r : g;
			gint32 mn = r < g ? r : g;
			if (b > mx)
				mx = b;
			if (b < mn)
				mn = b;
			const gint32 sat = mx - mn; /* 0..255 */
			if (sat == 0 || sat >= 255)
				continue;
			/* Rec.709 luma, 8.8 fixed point */
			const gint32 luma =
				(54 * r + 183 * g + 19 * b) >> 8;
			/* boost = amount * (1 - sat): strongest on muted */
			const gint32 boost =
				(amount_fx * (255 - sat)) / 255; /* 8.8 */
			const gint32 k = 256 + boost;
			gint32 nr = luma + (((r - luma) * k) >> 8);
			gint32 ng = luma + (((g - luma) * k) >> 8);
			gint32 nb = luma + (((b - luma) * k) >> 8);
			px[ro] = CLAMP(nr, 0, 255);
			px[1] = CLAMP(ng, 0, 255);
			px[bo] = CLAMP(nb, 0, 255);
		}
	}
	return GST_FLOW_OK;
}

static void
gst_vibrance_class_init(GstVibranceClass *klass)
{
	GObjectClass *gobject_class = G_OBJECT_CLASS(klass);
	GstElementClass *element_class = GST_ELEMENT_CLASS(klass);
	GstVideoFilterClass *vfilter_class = GST_VIDEO_FILTER_CLASS(klass);
	GstCaps *caps;

	gobject_class->set_property = gst_vibrance_set_property;
	gobject_class->get_property = gst_vibrance_get_property;

	g_object_class_install_property(
		gobject_class, PROP_AMOUNT,
		g_param_spec_double(
			"amount", "Amount",
			"Vibrance strength (0 = passthrough)",
			0.0, 2.0, 0.0,
			G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));

	gst_element_class_set_static_metadata(
		element_class, "Vibrance",
		"Filter/Effect/Video",
		"Saturation boost weighted towards muted colours",
		"cvs-dep-clear contributors");

	caps = gst_caps_from_string(VIBRANCE_CAPS);
	gst_element_class_add_pad_template(
		element_class,
		gst_pad_template_new("sink", GST_PAD_SINK, GST_PAD_ALWAYS,
				     caps));
	gst_element_class_add_pad_template(
		element_class,
		gst_pad_template_new("src", GST_PAD_SRC, GST_PAD_ALWAYS,
				     caps));
	gst_caps_unref(caps);

	vfilter_class->transform_frame_ip =
		GST_DEBUG_FUNCPTR(gst_vibrance_transform_frame_ip);
}

static void
gst_vibrance_init(GstVibrance *self)
{
	self->amount = 0.0;
}

static gboolean
plugin_init(GstPlugin *plugin)
{
	return gst_element_register(plugin, "vibrance", GST_RANK_NONE,
				    GST_TYPE_VIBRANCE);
}

GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, vibrance,
		  "Digital vibrance video filter", plugin_init, "1.0",
		  "LGPL", PACKAGE, "https://github.com/Carter-S/intel-cvs-dep-clear")
